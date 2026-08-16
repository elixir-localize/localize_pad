defmodule LocalizePad.Inversion do
  @moduledoc """
  Questions with a hole in them: `180 is what % off 200`, `20 is 10% of what`,
  `6 is to 60 as 8 is to what`.

  ## Why these are worth their own module

  Every other line in a sheet states an expression and asks for its value.
  These state the *value* and ask for a piece of the expression, and that is a
  different shape: `what` marks the unknown, and which unknown it is decides
  which arithmetic solves for it.

  They are also the forms people reach for when they cannot remember which way
  round the operation goes. Nobody is unsure how to divide; plenty of people
  are unsure whether "20% off" means multiplying by 0.8 or by 1.25, which is
  exactly why `180 is what % off 200` is worth being able to type.

  ## Off, of, and more than are three different questions

  * `180 is what % of 200` — 180 is 90% of 200.

  * `180 is what % off 200` — taking 10% off 200 gives 180.

  * `220 is what % more than 200` — 220 is 10% above 200.

  The same two numbers, three answers. Guessing which was meant is exactly the
  error the phrasing exists to avoid, so each is matched separately and a line
  that names none of them is refused rather than assigned a default.

  ## Word order is English

  The vocabulary lives in `LocalizePad.Lexicon` like every other word this
  program knows, but the *order* — value, `is`, hole, preposition, value — does
  not carry across languages, and swapping the vocabulary alone will not make
  `20 ist 10% von was` work. This is the limit the plan predicted: past a
  point, a locale needs phrase rules and not just words. It is reached here
  first, and honestly this is the place it was always going to be reached.

  """

  alias LocalizePad.{Lexicon, Percentage, Rate, Token}

  @type node_type :: {:inversion, atom(), map()}

  @doc """
  Recognises a question with a hole in it.

  ### Arguments

  * `tokens` - the tokens for one line.

  * `options` - a keyword list of options.

  ### Options

  * `:locale` - the locale whose vocabulary applies. Defaults to
    `Localize.get_locale/0`.

  ### Returns

  * `{:ok, {:inversion, kind, slots}}` when the line asks one of these
    questions.

  * `:error` otherwise, including for a line that says `what` but asks nothing
    this can solve.

  ### Examples

      iex> {:ok, tokens} = LocalizePad.Tokenizer.tokenize("180 is what % off 200", locale: :en)
      iex> {:ok, {:inversion, kind, _slots}} = LocalizePad.Inversion.match(tokens, locale: :en)
      iex> kind
      :percent_off

  """
  @spec match([Token.t()], keyword()) :: {:ok, node_type()} | :error
  def match(tokens, options \\ []) when is_list(tokens) do
    locale = Keyword.get_lazy(options, :locale, &Localize.get_locale/0)
    words = Enum.map(tokens, &String.downcase(&1.source))

    if Enum.any?(words, &Lexicon.what?(&1, lexicon_locale(locale))) do
      solve(tokens, words, lexicon_locale(locale))
    else
      :error
    end
  end

  # Ordered most specific first. `as` marks a proportion and would otherwise be
  # read as the conversion keyword it also is.
  defp solve(tokens, words, locale) do
    with :error <- proportion(tokens, words, locale),
         :error <- whole(tokens, words, locale),
         :error <- rate(tokens, words, locale) do
      percentage(tokens, words, locale)
    end
  end

  # `6 is to 60 as 8 is to what` — the fourth term of a proportion.
  defp proportion(tokens, words, locale) do
    numbers = Enum.filter(tokens, &(&1.kind == :number))

    if "as" in words and length(numbers) == 3 do
      [first, second, third] = Enum.map(numbers, & &1.value)

      {:ok, {:inversion, :proportion, %{a: first, b: second, c: third, locale: locale}}}
    else
      :error
    end
  end

  # `20 is 10% of what` — the whole a known percentage was taken from.
  defp whole(tokens, words, locale) do
    with true <- hole_follows?(tokens, words, locale, :of),
         [part | _rest] <- values(tokens),
         %Percentage{} = percentage <- find(tokens, :percentage) do
      {:ok, {:inversion, :whole, %{part: part, percentage: percentage, locale: locale}}}
    else
      _no_match -> :error
    end
  end

  # `$30/day is what per year` — the same amount stated over a different period.
  defp rate(tokens, _words, locale) do
    with %Rate{} = value <- find(tokens, :rate_value),
         {:ok, target} <- last_unit_after_hole(tokens, locale) do
      {:ok, {:inversion, :rate, %{rate: value, target: target, locale: locale}}}
    else
      _no_match -> :error
    end
  end

  # `180 is what % of 200`, and its two siblings. The preposition is the whole
  # question, so a line with none of them is refused.
  defp percentage(tokens, words, locale) do
    with {:ok, kind} <- comparison(words),
         [part, whole | _rest] <- values(tokens) do
      {:ok, {:inversion, kind, %{part: part, whole: whole, locale: locale}}}
    else
      _no_match -> :error
    end
  end

  defp comparison(words) do
    cond do
      "off" in words -> {:ok, :percent_off}
      "more" in words or "above" in words -> {:ok, :percent_more}
      "less" in words or "below" in words -> {:ok, :percent_less}
      "of" in words -> {:ok, :percent_of}
      true -> :error
    end
  end

  # Whether the hole sits *after* the named keyword, which is what separates
  # `20 is 10% of what` from `180 is what % of 200`.
  defp hole_follows?(tokens, words, locale, role) do
    hole = Enum.find_index(words, &Lexicon.what?(&1, locale))

    keyword =
      Enum.find_index(tokens, fn token ->
        token.kind == :keyword and token.value == role
      end)

    is_integer(hole) and is_integer(keyword) and hole > keyword
  end

  # The unit named after the hole — the `year` in `is what per year`.
  defp last_unit_after_hole(tokens, locale) do
    hole =
      Enum.find_index(tokens, fn token ->
        Lexicon.what?(String.downcase(token.source), locale)
      end)

    if is_integer(hole) do
      tokens
      |> Enum.drop(hole)
      |> Enum.find(&(&1.kind == :unit))
      |> case do
        nil -> :error
        token -> {:ok, token.value}
      end
    else
      :error
    end
  end

  # Money and numbers in the order they were written. Percentages are excluded
  # because they are the *known* part of these questions, never the operands.
  defp values(tokens) do
    tokens
    |> Enum.filter(&(&1.kind in [:number, :money]))
    |> Enum.map(& &1.value)
  end

  defp find(tokens, :percentage) do
    Enum.find_value(tokens, fn token ->
      if token.kind == :percentage, do: %Percentage{value: token.value}
    end)
  end

  # A rate is written as an amount over a unit, so it is assembled here rather
  # than looked up: the tokenizer has no reason to join them when the line is
  # not yet known to be a rate question.
  defp find(tokens, :rate_value) do
    with %{kind: :money, value: amount} <- Enum.find(tokens, &(&1.kind == :money)),
         %{kind: :unit, value: per} <- Enum.find(tokens, &(&1.kind == :unit)),
         {:ok, unit} <- Localize.Unit.new(1, per) do
      %Rate{amount: amount, per: unit}
    else
      _not_a_rate -> nil
    end
  end

  @doc """
  Solves a matched question.

  ### Arguments

  * `kind` - which question it is.

  * `slots` - the values the matcher extracted.

  ### Returns

  * `{:ok, value}`, or `{:error, reason}` when the numbers do not permit an
    answer — dividing by a whole of zero, most obviously.

  ### Examples

      iex> LocalizePad.Inversion.evaluate(:percent_off, %{part: 180, whole: 200, locale: :en})
      {:ok, %LocalizePad.Percentage{value: 10.0}}

  """
  @spec evaluate(atom(), map()) :: {:ok, term()} | {:error, term()}
  def evaluate(:percent_of, %{part: part, whole: whole}) do
    share(part, whole, fn part, whole -> part / whole end)
  end

  # `180 is what % off 200` — the fall from the whole, as a share of the whole.
  def evaluate(:percent_off, %{part: part, whole: whole}) do
    share(part, whole, fn part, whole -> (whole - part) / whole end)
  end

  # `220 is what % more than 200` — the rise above it, on the same base. Note
  # the base is the *smaller* number here and the larger one in `off`, which is
  # the whole reason these are separate questions.
  def evaluate(:percent_more, %{part: part, whole: whole}) do
    share(part, whole, fn part, whole -> (part - whole) / whole end)
  end

  def evaluate(:percent_less, %{part: part, whole: whole}) do
    share(part, whole, fn part, whole -> (whole - part) / whole end)
  end

  # `20 is 10% of what` — the whole that a known share was taken from.
  def evaluate(:whole, %{part: part, percentage: %Percentage{value: share}}) do
    cond do
      share == 0 -> {:error, :indeterminate}
      match?(%Money{}, part) -> {:ok, Money.mult!(part, 100 / share)}
      is_number(part) -> {:ok, part / (share / 100)}
      true -> {:error, {:incompatible, :whole, part}}
    end
  end

  # `6 is to 60 as 8 is to what` — the fourth term.
  def evaluate(:proportion, %{a: a, b: b, c: c}) do
    if a == 0 do
      {:error, :indeterminate}
    else
      {:ok, b * c / a}
    end
  end

  # `$30/day is what per year`. Conversion already knows how to restate a rate
  # over a different period, so this only has to ask it.
  def evaluate(:rate, %{rate: rate, target: target}) do
    with {:ok, unit} <- Localize.Unit.new(1, target) do
      Rate.convert(rate, unit)
    end
  end

  def evaluate(kind, _slots), do: {:error, {:unsupported_question, kind}}

  # The three comparisons differ only in the fraction they form, so the
  # arithmetic that turns one into an answer is written once.
  defp share(part, whole, fraction) do
    with {:ok, part} <- as_number(part),
         {:ok, whole} <- as_number(whole) do
      if whole == 0 do
        {:error, :indeterminate}
      else
        {:ok, %Percentage{value: fraction.(part, whole) * 100}}
      end
    end
  end

  # A percentage of two money amounts is a plain percentage, so the currency
  # falls away — but only when both sides agree, because the ratio of dollars
  # to euros is not a number this can produce.
  defp as_number(%Money{} = money), do: {:ok, money |> Money.to_decimal() |> Decimal.to_float()}
  defp as_number(value) when is_number(value), do: {:ok, value}
  defp as_number(%Decimal{} = value), do: {:ok, Decimal.to_float(value)}
  defp as_number(other), do: {:error, {:incompatible, :question, other}}

  defp lexicon_locale(locale) do
    case Localize.validate_locale(locale) do
      {:ok, tag} -> String.to_existing_atom(to_string(tag.language))
      {:error, _reason} -> :en
    end
  rescue
    ArgumentError -> :en
  end
end
