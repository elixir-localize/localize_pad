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

  alias LocalizePad.{Almanac, Finance, Inversion, Token}
  alias LocalizePad.Temporal.{Recurrence, Uncertain, Workdays}

  # {left, right} binding powers. Right < left makes an operator
  # right-associative, which is why `:pow` is {11, 10}.
  @binding_powers %{
    # Loosest of all, so both operands are complete spans:
    # `9am to 5pm London and 9am to 5pm New York`.
    intersect: {1, 2},
    to: {3, 4},
    plus: {5, 6},
    minus: {5, 6},
    times: {7, 8},
    divide: {7, 8},
    per: {7, 8},
    power: {13, 12},
    # Relative-date phrases bind as loosely as `to`, so the whole expression
    # on either side is the operand: `3 weeks + 2 days after March 14`.
    after: {3, 4},
    before: {3, 4},
    # `10% of 200` and its siblings. Loose, so the whole expression on either
    # side is the operand.
    of: {3, 4},
    off: {3, 4},
    on: {3, 4},
    # Same binding as the roles they mirror; only the operand order differs.
    of_reversed: {3, 4},
    per_reversed: {7, 8}
  }

  # Juxtaposition binds tighter than explicit `*` and `/`, so `kg m / s` parses
  # as `(kg × m) / s` — matching GNU `units`, and matching what people mean.
  @juxtaposition {9, 10}

  # Unary minus binds tighter than any infix operator except exponentiation.
  @prefix_binding_power 11

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
          | {:calendar, module()}
          | {:preference, term(), atom()}
          | {:neg, ast()}
          | {:binary, atom(), ast(), ast()}
          | {:convert, ast(), ast()}
          | {:phrase, :of | :off | :on, ast(), ast()}
          | {:finance, atom(), map()}
          | {:recurrence, String.t(), Date.t()}
          | {:workdays, atom(), map()}
          | {:uncertain, String.t()}
          | {:inversion, atom(), map()}

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
      {:ok, node} ->
        {:ok, node}

      :error ->
        phrase(tokens, variables, Keyword.take(options, [:locale, :reference_date, :zone]))
    end
  end

  # Each phrase matcher looks at the whole line and either claims it or passes.
  # Ordinary expression parsing is the fallback.
  defp phrase(tokens, variables, options) do
    with :error <- Inversion.match(tokens, options),
         :error <- Workdays.match(tokens, options),
         :error <- Uncertain.match(tokens),
         :error <- Recurrence.match(tokens, options),
         # Last, so that a line which is a recurrence *and* names an event —
         # `sunrise every Monday` — keeps the reading it already had rather
         # than quietly losing its `every`.
         :error <- Almanac.match(tokens, options) do
      parse_expression_tokens(tokens, variables)
    else
      {:ok, node} -> {:ok, node}
    end
  end

  defp parse_expression_tokens(tokens, variables) do
    case tokens |> skip_noise(variables) |> parse_expression(0, variables) do
      {:ok, ast, rest} ->
        leftover(ast, rest, variables)

      {:error, :no_expression} ->
        {:error, :no_expression}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # What is left after a complete expression. Prose ends the sum: `19 + 22 for
  # 2 coffees` is forty-one and a remark, and the `2` in the remark is part of
  # the remark. Once a word we cannot read has been stepped over, everything
  # past it is commentary — which is the rule the whole tokenizer runs on,
  # applied to the tail of the line rather than the middle.
  #
  # Leftovers that start *without* prose are a genuine parse failure and still
  # report one, so `2 (1 + 1)` is an error rather than a silent `2`.
  defp leftover(ast, rest, variables) do
    case skip_noise(rest, variables) do
      [] -> {:ok, ast}
      ^rest -> {:error, {:unexpected, hd(rest).source}}
      remaining -> discard_or_refuse(ast, remaining)
    end
  end

  # Commentary is text with no quantity in it. A trailing *unit* is not
  # commentary — `99 EUR per week` on a German sheet is somebody asking for a
  # rate in a word this locale does not know, and answering `99 €` would drop
  # what they asked for and look like agreement. That refuses, where
  # `19 + 22 for 2 coffees` answers forty-one: the coffees carry no reading, so
  # there is nothing to lose by ignoring them.
  #
  # A bare number is not enough to count. Numbers appear in prose all the time
  # — two coffees, three of us — and it is the *unit* that says the writer
  # meant a quantity rather than a remark.
  #
  # An *operator* counts for the same reason. `1.234,5 + 1` on a French sheet
  # scans as `1`, a stray `.`, then `234,5 + 1`, because a French reader does
  # not write thousands that way. Swallowing the tail there answered `1` — the
  # first number of a sum the reader plainly meant, with the rest discarded as
  # though it were a remark about coffee.
  @meaningful [
    :unit,
    :money,
    :percentage,
    :temporal,
    :currency,
    :zone,
    :calendar,
    :preference,
    :operator
  ]

  defp discard_or_refuse(ast, remaining) do
    case Enum.find(remaining, &(&1.kind in @meaningful)) do
      nil -> {:ok, ast}
      token -> {:error, {:unexpected, token.source}}
    end
  end

  # ── Expression parsing ──────────────────────────────────────────────────

  defp parse_expression(tokens, minimum_binding_power, variables) do
    with {:ok, left, rest} <-
           tokens
           |> skip_to_operand(variables)
           |> parse_prefix(variables, minimum_binding_power) do
      parse_infix(left, rest, minimum_binding_power, variables)
    end
  end

  # A prefix position is where an operand is expected. `in` read here means the
  # unit `inch`, not the conversion keyword — position is what disambiguates.
  defp parse_prefix([], _variables, _binding_power), do: {:error, :no_expression}

  defp parse_prefix([%Token{kind: kind, value: value} | rest], _variables, _binding_power)
       when kind in [:number, :ordinal] do
    {:ok, {:number, value}, rest}
  end

  # A name the sheet declared beats the unit dictionary. `week = 5` says what
  # `week` means on the lines below it, and reading the next one as five weeks
  # ignores the only statement of intent on the page.
  #
  # It bites hardest outside English, where the commonest words are units:
  # `año`, `Jahr`, `Tag`, `semaine`, `heure`. A reader naming a variable after
  # an everyday noun is doing the ordinary thing, and `año = 12` followed by
  # `año * 2` answered `2 años`.
  #
  # Only in operand position. A unit *reading* is still what `3 semaines`
  # wants, and that is settled by the token to its left rather than here.
  defp parse_prefix(
         [%Token{kind: :unit, value: unit, source: source} | rest],
         variables,
         _binding_power
       ) do
    if MapSet.member?(variables, source) do
      {:ok, {:variable, source}, rest}
    else
      {:ok, {:unit, unit}, rest}
    end
  end

  defp parse_prefix([%Token{kind: :line_ref, value: line} | rest], _variables, _binding_power) do
    {:ok, {:line_ref, line}, rest}
  end

  defp parse_prefix([%Token{kind: :temporal, value: fields} | rest], _variables, _binding_power) do
    {:ok, {:temporal, fields}, rest}
  end

  defp parse_prefix([%Token{kind: :zone, value: zone} | rest], _variables, _binding_power) do
    {:ok, {:zone, zone}, rest}
  end

  defp parse_prefix([%Token{kind: :percentage, value: value} | rest], _variables, _binding_power) do
    {:ok, {:percentage, value}, rest}
  end

  defp parse_prefix([%Token{kind: :money, value: money} | rest], _variables, _binding_power) do
    {:ok, {:money, money}, rest}
  end

  defp parse_prefix([%Token{kind: :currency, value: code} | rest], _variables, _binding_power) do
    {:ok, {:currency, code}, rest}
  end

  defp parse_prefix([%Token{kind: :tax, value: tax} | rest], _variables, _binding_power) do
    {:ok, {:tax, tax}, rest}
  end

  defp parse_prefix(
         [%Token{kind: :preference, value: {locale, usage}} | rest],
         _variables,
         _binding_power
       ) do
    {:ok, {:preference, locale, usage}, rest}
  end

  defp parse_prefix([%Token{kind: :calendar, value: calendar} | rest], _variables, _binding_power) do
    {:ok, {:calendar, calendar}, rest}
  end

  defp parse_prefix([%Token{kind: :operator, value: :minus} | rest], variables, _binding_power) do
    with {:ok, operand, rest} <- parse_expression(rest, @prefix_binding_power, variables) do
      {:ok, {:neg, operand}, rest}
    end
  end

  defp parse_prefix([%Token{kind: :operator, value: :plus} | rest], variables, _binding_power) do
    parse_expression(rest, @prefix_binding_power, variables)
  end

  defp parse_prefix([%Token{kind: :operator, value: :lparen} | rest], variables, _binding_power) do
    with {:ok, inner, rest} <- parse_expression(rest, 0, variables) do
      case skip_noise(rest, variables) do
        [%Token{kind: :operator, value: :rparen} | rest] -> {:ok, inner, rest}
        _other -> {:error, :unclosed_parenthesis}
      end
    end
  end

  # A bare unit is not an expression. `inch` on its own is not a value, so the
  # unit reading is only available where something can multiply it — as the
  # right operand of an operation, which is the `3 in` case and is what a
  # non-zero binding power means here.
  #
  # Without that condition a line-leading `in 3 weeks` reads its `in` as inch
  # and answers "3 inch-weeks", which is worse than refusing: the reader has to
  # already know the answer to notice it is wrong.
  defp parse_prefix([%Token{kind: :keyword} = token | rest], _variables, binding_power)
       when binding_power > 0 do
    case Token.as(token, :unit) do
      {:ok, unit} -> {:ok, {:unit, unit}, rest}
      :error -> {:error, {:unexpected, token.source}}
    end
  end

  defp parse_prefix([%Token{kind: :keyword} = token | _rest], _variables, _binding_power) do
    {:error, {:unexpected, token.source}}
  end

  defp parse_prefix([%Token{kind: :word} | _rest] = tokens, variables, _binding_power) do
    case take_variable(tokens, variables) do
      {:ok, name, rest} -> {:ok, {:variable, name}, rest}
      :error -> {:error, :no_expression}
    end
  end

  defp parse_prefix([token | _rest], _variables, _binding_power) do
    {:error, {:unexpected, token.source}}
  end

  # An infix position is where an operator is expected. `in` read here is the
  # conversion keyword.
  # `42 km locally` and `70 kg lokal`. The target follows the value with no
  # operator between them, which is the natural word order in every locale this
  # ships — `in local units` reads well in English and `in lokal` does not, so
  # the postfix form is what makes the vocabulary usable rather than a phrase
  # that only parses in one language.
  #
  # It binds as loosely as `to`, being the same conversion, so the whole
  # expression to its left is the operand: `40 km + 2 km locally`.
  defp parse_infix(left, tokens, minimum_binding_power, variables)
       when minimum_binding_power <= 3 do
    case skip_noise(tokens, variables) do
      [%Token{kind: :preference, value: {locale, usage}} | rest] ->
        {:convert, left, {:preference, locale, usage}}
        |> parse_infix(rest, minimum_binding_power, variables)

      remaining ->
        infix(left, remaining, minimum_binding_power, variables, tokens)
    end
  end

  defp parse_infix(left, tokens, minimum_binding_power, variables) do
    infix(left, skip_noise(tokens, variables), minimum_binding_power, variables, tokens)
  end

  # `original` is the token list before prose was stepped over, and the only
  # thing that cares is juxtaposition. `19 + 22 for 2 coffees` is one sum and a
  # remark about coffee, not `22 × 2` — implicit multiplication means two
  # operands written *next to each other*, and words in between are exactly the
  # evidence that they were not. `3 meters` still multiplies, because nothing
  # separates them.
  #
  # Stopping hands back `original` rather than the skipped list, so the words
  # are still there for the caller to treat as trailing prose. Returning the
  # skipped list instead lets a looser level juxtapose the very operand this
  # clause just refused, which is how `19 + 22 for 2 coffees` became 82.
  defp infix(left, tokens, minimum_binding_power, variables, original) do
    case infix_operator(tokens, variables) do
      {:ok, :juxtapose, _binding_powers, _rest} when tokens != original ->
        {:ok, left, original}

      {:ok, operator, {left_binding_power, right_binding_power}, rest}
      when left_binding_power >= minimum_binding_power ->
        with {:ok, right, rest} <- parse_expression(rest, right_binding_power, variables) do
          left
          |> combine(operator, right)
          |> parse_infix(rest, minimum_binding_power, variables)
        end

      # Nothing here continues the expression, so the prose that was stepped
      # over on the way in was never consumed. Hand back the tokens as they
      # arrived, or the caller sees a leftover starting mid-remark and reports
      # the wrong word — `19 + 22 for 2 coffees` blamed the `2`.
      _stop ->
        {:ok, left, original}
    end
  end

  defp combine(left, :to, right), do: {:convert, left, right}
  defp combine(left, :intersect, right), do: {:binary, :intersect, left, right}

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

  # A postpositional particle puts its operands the other way round: `700の20%`
  # is "20% of 700" and `1日あたり100` is "100 per day". Swapping here keeps one
  # evaluator for both word orders — the alternative was a second set of
  # arithmetic clauses that differ only in which side they read first.
  defp combine(left, :of_reversed, right), do: {:phrase, :of, right, left}
  defp combine(left, :per_reversed, right), do: {:binary, :div, right, left}
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
    case keyword_reading(token, rest, variables) do
      :unit ->
        {:ok, :juxtapose, @juxtaposition, tokens}

      :keyword ->
        case Map.fetch(@binding_powers, role) do
          {:ok, binding_powers} -> {:ok, role, binding_powers, rest}
          :error -> :none
        end
    end
  end

  # `19-22`. The number scanner reads a hyphen between digits as a sign, so this
  # arrives as two numbers, the second negative — and adding a negative is the
  # subtraction the reader wrote. Without this the line had no reading at all,
  # because two bare numbers side by side are not a product.
  #
  # Only when the number is *negative*: `19 22` stays two numbers, which is
  # what lets a space-grouped `1 234,5` be one and `19 22` be two.
  defp infix_operator([%Token{kind: :number, value: value} | _rest] = tokens, _variables)
       when is_number(value) and value < 0 do
    {:ok, :plus, Map.fetch!(@binding_powers, :plus), tokens}
  end

  # Anything that could begin an operand, sitting next to the previous operand,
  # is implicit multiplication: `3 meters`, `kg m`, `2 (1 + 1)`.
  #
  # A bare number is deliberately absent. Two numbers side by side is a reading
  # nobody writes — `2 3` is not how anyone means six — and it was actively
  # harmful: `5 000` answered `0`, and `19 22` answered `418`. Both are far
  # likelier to be a number written with a space between its groups, which is
  # how French and a dozen other locales group thousands.
  #
  # `3 meters` still multiplies. The juxtaposition there is triggered by the
  # *unit*, not by the number before it, so removing numbers from this list
  # costs none of the cases the rule exists for.
  defp infix_operator([%Token{kind: kind} | _rest] = tokens, _variables)
       when kind in [:unit, :line_ref, :temporal, :zone, :percentage, :money] do
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

  # A keyword that also names a unit, with nothing after it to operate on, is
  # the unit. `12 ft + 3 in` ends in three inches; reading `in` as conversion
  # would leave the line malformed for want of a target.
  #
  # That guess is sometimes wrong — `19 + 22 in cash` is not about inches — but
  # nothing here can tell, because both readings parse. What distinguishes them
  # is whether the units agree, which only evaluation knows. See
  # `LocalizePad.Line`, which retries with the reading demoted when they do not.
  defp keyword_reading(token, rest, variables) do
    cond do
      not Token.is?(token, :unit) -> :keyword
      operand_follows?(rest, variables) -> :keyword
      true -> :unit
    end
  end

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
             :tax,
             :calendar,
             :preference
           ] ->
        true

      # A parenthesis can open a conversion target; a sign cannot. Nothing is
      # ever converted *to* a signed number, and counting `+` here read the
      # `in` of `3 in + 2 in` as a conversion — which asked to convert three of
      # nothing into two inches and refused the line.
      [%Token{kind: :operator, value: operator} | _rest] ->
        operator == :lparen

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
