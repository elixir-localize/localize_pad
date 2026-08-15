defmodule LocalizePad.Parser do
  @moduledoc """
  A precedence-climbing (Pratt) parser over `LocalizePad.Token` streams.

  ## Why not a parser combinator

  Unity parses the same arithmetic with NimbleParsec, and for a strict grammar
  that is the better tool. This language is not strict. It has to skip words it
  does not understand, resolve `in` differently depending on where it appears,
  and swap its operator vocabulary at runtime when the sheet's locale changes —
  none of which sit comfortably with committed-choice combinators built at
  compile time. Precedence climbing over a token list gives all three for less
  code, and phrase rules can pattern-match the same list directly.

  ## The AST

  Deliberately small. A unit is an ordinary operand meaning "one of these", so
  `3 meters` needs no special node — it is `3 × meter`, exactly as GNU `units`
  models it. That one decision removes quantity, compound-unit and
  juxtaposition nodes from the tree:

  * `{:number, value}`

  * `{:unit, cldr_name}` — one of that unit.

  * `{:variable, name}`

  * `{:line_ref, line_number}` — `@3`, the answer on line 3.

  * `{:temporal, fields}` — a date or time, as the partial field map the
    scanner recovered.

  * `{:zone, zone}` — a time zone, only meaningful next to a temporal value.

  * `{:neg, expr}`

  * `{:binary, operator, left, right}` where operator is `:add`, `:sub`,
    `:mul`, `:div` or `:pow`.

  * `{:convert, expr, target}` — `3 m to ft`.

  * `{:phrase, preposition, left, right}` — `10% of 200`, `VAT on $300`.

  ## Noise

  Words that name no variable are skipped wherever they appear, which is what
  makes `$19 for breakfast + $22 for the uber` evaluate to 41. Because a
  variable reference is also a bare word, the parser needs to know which names
  are bound; pass them with the `:variables` option.

  """

  alias LocalizePad.{Finance, Token}

  # {left, right} binding powers. Right < left makes an operator
  # right-associative, which is why `:pow` is {11, 10}.
  @binding_powers %{
    to: {1, 2},
    plus: {3, 4},
    minus: {3, 4},
    times: {5, 6},
    divide: {5, 6},
    per: {5, 6},
    power: {11, 10},
    # Relative-date phrases bind as loosely as `to`, so the whole expression
    # on either side is the operand: `3 weeks + 2 days after March 14`.
    after: {1, 2},
    before: {1, 2},
    # `10% of 200` and its siblings. Loose, so the whole expression on either
    # side is the operand.
    of: {1, 2},
    off: {1, 2},
    on: {1, 2}
  }

  # Juxtaposition binds tighter than explicit `*` and `/`, so `kg m / s` parses
  # as `(kg × m) / s` — matching GNU `units`, and matching what people mean.
  @juxtaposition {7, 8}

  # Unary minus binds tighter than any infix operator except exponentiation.
  @prefix_binding_power 9

  @operator_nodes %{
    plus: :add,
    minus: :sub,
    times: :mul,
    divide: :div,
    power: :pow
  }

  @type ast ::
          {:number, number() | Decimal.t()}
          | {:unit, String.t()}
          | {:variable, String.t()}
          | {:line_ref, pos_integer()}
          | {:temporal, map()}
          | {:zone, LocalizePad.Temporal.Zones.t()}
          | {:percentage, number()}
          | {:money, Money.t()}
          | {:currency, atom()}
          | {:tax, LocalizePad.SalesTax.t()}
          | {:neg, ast()}
          | {:binary, atom(), ast(), ast()}
          | {:convert, ast(), ast()}
          | {:phrase, :of | :off | :on, ast(), ast()}
          | {:finance, atom(), map()}

  @doc """
  Parses a token stream into an AST.

  ### Arguments

  * `tokens` - the tokens produced by `LocalizePad.Tokenizer.tokenize/2`.

  * `options` - a keyword list of options.

  ### Options

  * `:variables` - the names currently bound in the sheet, as a list or
    `MapSet`. A bare word matching one of these parses as a variable
    reference; every other bare word is discarded as prose. Defaults to `[]`.

  ### Returns

  * `{:ok, ast}` when the tokens describe a calculation.

  * `{:error, :no_expression}` when the line carries no arithmetic at all —
    an empty line, or pure prose. This is an ordinary outcome, not a fault.

  * `{:error, reason}` for a malformed expression, such as an operator with
    nothing to its right.

  ### Examples

      iex> {:ok, tokens} = LocalizePad.Tokenizer.tokenize("2 + 3", locale: :en)
      iex> LocalizePad.Parser.parse(tokens)
      {:ok, {:binary, :add, {:number, 2}, {:number, 3}}}

      iex> {:ok, tokens} = LocalizePad.Tokenizer.tokenize("3 meters", locale: :en)
      iex> LocalizePad.Parser.parse(tokens)
      {:ok, {:binary, :mul, {:number, 3}, {:unit, "meter"}}}

      iex> {:ok, tokens} = LocalizePad.Tokenizer.tokenize("just a thought", locale: :en)
      iex> LocalizePad.Parser.parse(tokens)
      {:error, :no_expression}

  """
  @spec parse([Token.t()], keyword()) :: {:ok, ast()} | {:error, atom()}
  def parse(tokens, options \\ []) when is_list(tokens) do
    variables = options |> Keyword.get(:variables, []) |> MapSet.new()

    # Financial phrases have three or four slots and no fixed word order, so
    # they are recognised whole rather than assembled from infix operators.
    # See `LocalizePad.Finance`.
    case Finance.match(tokens) do
      {:ok, node} -> {:ok, node}
      :error -> parse_expression_tokens(tokens, variables)
    end
  end

  defp parse_expression_tokens(tokens, variables) do
    case tokens |> skip_noise(variables) |> parse_expression(0, variables) do
      {:ok, ast, rest} ->
        case skip_noise(rest, variables) do
          [] -> {:ok, ast}
          [token | _rest] -> {:error, {:unexpected, token.source}}
        end

      {:error, :no_expression} ->
        {:error, :no_expression}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ── Expression parsing ──────────────────────────────────────────────────

  defp parse_expression(tokens, minimum_binding_power, variables) do
    with {:ok, left, rest} <- tokens |> skip_to_operand(variables) |> parse_prefix(variables) do
      parse_infix(left, rest, minimum_binding_power, variables)
    end
  end

  # A prefix position is where an operand is expected. `in` read here means the
  # unit `inch`, not the conversion keyword — position is what disambiguates.
  defp parse_prefix([], _variables), do: {:error, :no_expression}

  defp parse_prefix([%Token{kind: :number, value: value} | rest], _variables) do
    {:ok, {:number, value}, rest}
  end

  defp parse_prefix([%Token{kind: :unit, value: unit} | rest], _variables) do
    {:ok, {:unit, unit}, rest}
  end

  defp parse_prefix([%Token{kind: :line_ref, value: line} | rest], _variables) do
    {:ok, {:line_ref, line}, rest}
  end

  defp parse_prefix([%Token{kind: :temporal, value: fields} | rest], _variables) do
    {:ok, {:temporal, fields}, rest}
  end

  defp parse_prefix([%Token{kind: :zone, value: zone} | rest], _variables) do
    {:ok, {:zone, zone}, rest}
  end

  defp parse_prefix([%Token{kind: :percentage, value: value} | rest], _variables) do
    {:ok, {:percentage, value}, rest}
  end

  defp parse_prefix([%Token{kind: :money, value: money} | rest], _variables) do
    {:ok, {:money, money}, rest}
  end

  defp parse_prefix([%Token{kind: :currency, value: code} | rest], _variables) do
    {:ok, {:currency, code}, rest}
  end

  defp parse_prefix([%Token{kind: :tax, value: tax} | rest], _variables) do
    {:ok, {:tax, tax}, rest}
  end

  defp parse_prefix([%Token{kind: :operator, value: :minus} | rest], variables) do
    with {:ok, operand, rest} <- parse_expression(rest, @prefix_binding_power, variables) do
      {:ok, {:neg, operand}, rest}
    end
  end

  defp parse_prefix([%Token{kind: :operator, value: :plus} | rest], variables) do
    parse_expression(rest, @prefix_binding_power, variables)
  end

  defp parse_prefix([%Token{kind: :operator, value: :lparen} | rest], variables) do
    with {:ok, inner, rest} <- parse_expression(rest, 0, variables) do
      case skip_noise(rest, variables) do
        [%Token{kind: :operator, value: :rparen} | rest] -> {:ok, inner, rest}
        _other -> {:error, :unclosed_parenthesis}
      end
    end
  end

  defp parse_prefix([%Token{kind: :keyword} = token | rest], _variables) do
    # A keyword in operand position is only meaningful if it has a unit
    # reading — this is the `3 in` case.
    case Token.as(token, :unit) do
      {:ok, unit} -> {:ok, {:unit, unit}, rest}
      :error -> {:error, {:unexpected, token.source}}
    end
  end

  defp parse_prefix([%Token{kind: :word} | _rest] = tokens, variables) do
    case take_variable(tokens, variables) do
      {:ok, name, rest} -> {:ok, {:variable, name}, rest}
      :error -> {:error, :no_expression}
    end
  end

  defp parse_prefix([token | _rest], _variables) do
    {:error, {:unexpected, token.source}}
  end

  # An infix position is where an operator is expected. `in` read here is the
  # conversion keyword.
  defp parse_infix(left, tokens, minimum_binding_power, variables) do
    tokens = skip_noise(tokens, variables)

    case infix_operator(tokens, variables) do
      {:ok, operator, {left_binding_power, right_binding_power}, rest}
      when left_binding_power >= minimum_binding_power ->
        with {:ok, right, rest} <- parse_expression(rest, right_binding_power, variables) do
          left
          |> combine(operator, right)
          |> parse_infix(rest, minimum_binding_power, variables)
        end

      _stop ->
        {:ok, left, tokens}
    end
  end

  defp combine(left, :to, right), do: {:convert, left, right}

  # `3 weeks after March 14` is `March 14 + 3 weeks` with the operands
  # reversed, and `3 days before` is the same with a subtraction.
  defp combine(left, :after, right), do: {:binary, :add, right, left}
  defp combine(left, :before, right), do: {:binary, :sub, right, left}

  # `10% of 200`, `VAT on $300`. The preposition is kept in the tree rather
  # than lowered to arithmetic here, because it carries meaning the operands
  # cannot recover: `VAT on $300` treats $300 as a net price and `VAT of $300`
  # treats it as a gross one, and the two give different answers.
  defp combine(left, role, right) when role in [:of, :off, :on] do
    {:phrase, role, left, right}
  end

  defp combine(left, :per, right), do: {:binary, :div, left, right}
  defp combine(left, :juxtapose, right), do: {:binary, :mul, left, right}
  defp combine(left, operator, right), do: {:binary, @operator_nodes[operator], left, right}

  defp infix_operator([%Token{kind: :operator, value: :rparen} | _rest], _variables) do
    :none
  end

  defp infix_operator([%Token{kind: :operator, value: operator} | rest], _variables) do
    case Map.fetch(@binding_powers, operator) do
      {:ok, binding_powers} -> {:ok, operator, binding_powers, rest}
      :error -> :none
    end
  end

  defp infix_operator([%Token{kind: :keyword, value: role} = token | rest] = tokens, variables) do
    # A keyword that also names a unit, with nothing after it to operate on, is
    # the unit. `12 ft + 3 in` ends in three inches; reading `in` as conversion
    # would leave the line malformed for want of a target.
    if Token.is?(token, :unit) and not operand_follows?(rest, variables) do
      {:ok, :juxtapose, @juxtaposition, tokens}
    else
      case Map.fetch(@binding_powers, role) do
        {:ok, binding_powers} -> {:ok, role, binding_powers, rest}
        :error -> :none
      end
    end
  end

  # Anything that could begin an operand, sitting next to the previous operand,
  # is implicit multiplication: `3 meters`, `kg m`, `2 (1 + 1)`.
  defp infix_operator([%Token{kind: kind} | _rest] = tokens, _variables)
       when kind in [:number, :unit, :line_ref, :temporal, :zone, :percentage, :money] do
    {:ok, :juxtapose, @juxtaposition, tokens}
  end

  defp infix_operator([%Token{kind: :operator, value: :lparen} | _rest] = tokens, _variables) do
    {:ok, :juxtapose, @juxtaposition, tokens}
  end

  defp infix_operator([%Token{kind: :word} | _rest] = tokens, variables) do
    case take_variable(tokens, variables) do
      {:ok, _name, _rest} -> {:ok, :juxtapose, @juxtaposition, tokens}
      :error -> :none
    end
  end

  defp infix_operator(_tokens, _variables), do: :none

  # Whether anything ahead could serve as an operand, once prose is skipped.
  # Used to decide between the two readings of an ambiguous keyword.
  defp operand_follows?(tokens, variables) do
    case skip_to_operand(tokens, variables) do
      [] ->
        false

      [%Token{kind: kind} | _rest]
      when kind in [
             :number,
             :unit,
             :word,
             :line_ref,
             :temporal,
             :zone,
             :percentage,
             :money,
             :currency,
             :tax
           ] ->
        true

      [%Token{kind: :operator, value: operator} | _rest] ->
        operator in [:lparen, :minus, :plus]

      [%Token{kind: :keyword} = token | _rest] ->
        Token.is?(token, :unit)

      _other ->
        false
    end
  end

  # ── Noise and variables ─────────────────────────────────────────────────

  # Drop leading words that name no variable. Everything else — including a
  # word that *does* name a variable — is left in place.
  #
  # Used in infix position, where a keyword is an operator and must survive.
  defp skip_noise([%Token{kind: :word} | rest] = tokens, variables) do
    case take_variable(tokens, variables) do
      {:ok, _name, _remaining} -> tokens
      :error -> skip_noise(rest, variables)
    end
  end

  defp skip_noise(tokens, _variables), do: tokens

  # Used in prefix position, where an operand is expected. Drops the same
  # non-variable words, and additionally drops keywords that carry no unit
  # reading — in that position they are prose, not operators.
  #
  # This matters more than it looks: `a` is a surface form of the `:per` role
  # (as in "$24 a day"), so without this `just a thought` would fail as a
  # malformed expression rather than being recognised as an ordinary sentence.
  defp skip_to_operand([%Token{kind: :keyword} = token | rest] = tokens, variables) do
    if Token.is?(token, :unit) do
      tokens
    else
      skip_to_operand(rest, variables)
    end
  end

  defp skip_to_operand([%Token{kind: :word} | rest] = tokens, variables) do
    case take_variable(tokens, variables) do
      {:ok, _name, _remaining} -> tokens
      :error -> skip_to_operand(rest, variables)
    end
  end

  defp skip_to_operand(tokens, _variables), do: tokens

  # Variable names may be phrases ("monthly rent"), so match the longest run of
  # words that names something bound. Longest-first matters: with both `rent`
  # and `monthly rent` bound, `monthly rent` must win.
  defp take_variable(tokens, variables) do
    words = Enum.take_while(tokens, &(&1.kind == :word))

    words
    |> Enum.count()
    |> countdown()
    |> Enum.find_value(:error, fn length ->
      name = words |> Enum.take(length) |> Enum.map_join(" ", & &1.source)

      if MapSet.member?(variables, name) do
        {:ok, name, Enum.drop(tokens, length)}
      end
    end)
  end

  defp countdown(0), do: []
  defp countdown(count), do: Enum.to_list(count..1//-1)
end
