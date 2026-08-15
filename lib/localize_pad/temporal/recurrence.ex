defmodule LocalizePad.Temporal.Recurrence do
  @moduledoc """
  Recurring dates: `every Friday the 13th`, `4th Thursday of November`,
  `last weekday of every month`.

  ## Why this is worth having

  Soulver has no recurrence at all, and it is the clearest case of a question
  people genuinely ask that a notepad calculator has never answered. "When is
  the next Friday the 13th" is a lookup in a calendar app and a one-liner here.

  ## Phrases in, RRULE out

  Every phrase compiles to an RFC 5545 rule string and is handed to
  `Tempo.RRule.parse!/2`. Nothing about recurrence is implemented here — the
  whole job is turning English into a rule the library already understands,
  which is why the module is mostly tables.

  ## Weekday and month names come from CLDR

  The names are read from `Localize.Calendar`, so the phrase vocabulary is
  already localized: `jeden Freitag` needs only the operator words, not a
  second list of weekday names. The ordinals (`first`, `4th`, `last`) are the
  part that still needs authoring per locale, and they live with the rest of
  the operator lexicon.

  ## Answers are sets

  A recurrence has no single answer, so this returns a `Tempo.IntervalSet`.
  The count is bounded because most rules are infinite; see `@default_count`.

  """

  alias LocalizePad.Token

  # Enough occurrences to answer "when is the next one" and see the pattern,
  # few enough to render in a margin. A stated year bounds it instead.
  @default_count 5

  @weekday_codes %{1 => "MO", 2 => "TU", 3 => "WE", 4 => "TH", 5 => "FR", 6 => "SA", 7 => "SU"}

  @ordinals %{
    "first" => 1,
    "1st" => 1,
    "second" => 2,
    "2nd" => 2,
    "third" => 3,
    "3rd" => 3,
    "fourth" => 4,
    "4th" => 4,
    "fifth" => 5,
    "5th" => 5,
    "last" => -1
  }

  @doc """
  Recognises a recurrence phrase.

  ### Arguments

  * `tokens` - the tokens for one line.

  * `options` - a keyword list of options.

  ### Options

  * `:locale` - the locale whose weekday and month names apply. Defaults to
    `Localize.get_locale/0`.

  ### Returns

  * `{:ok, {:recurrence, rule, from}}` where `rule` is an RFC 5545 rule string
    and `from` is the date to start searching at.

  * `:error` when the line is not a recurrence.

  ### Examples

      iex> {:ok, tokens} =
      ...>   LocalizePad.Tokenizer.tokenize("every Friday the 13th", locale: :en)
      iex> {:ok, {:recurrence, rule, _from}} =
      ...>   LocalizePad.Temporal.Recurrence.match(tokens, locale: :en)
      iex> rule
      "FREQ=MONTHLY;BYMONTHDAY=13;BYDAY=FR;COUNT=5"

  """
  @spec match([Token.t()], keyword()) :: {:ok, {:recurrence, String.t(), Date.t()}} | :error
  def match(tokens, options \\ []) when is_list(tokens) do
    locale = Keyword.get_lazy(options, :locale, &Localize.get_locale/0)
    words = Enum.map(tokens, &String.downcase(&1.source))

    if recurring?(words, tokens) do
      build(words, tokens, locale, options)
    else
      :error
    end
  end

  # `every` marks a recurrence outright; an ordinal-plus-weekday phrase is one
  # even without it, as in `4th Thursday of November`.
  defp recurring?(words) do
    "every" in words or "each" in words or Enum.any?(words, &Map.has_key?(@ordinals, &1))
  end

  defp recurring?(words, tokens) do
    recurring?(words) or Enum.any?(tokens, &(&1.kind == :ordinal))
  end

  defp build(words, tokens, locale, options) do
    with {:ok, rule} <- rule(words, tokens, locale) do
      {:ok, {:recurrence, bound(rule, words, tokens), start_date(tokens, options)}}
    end
  end

  defp rule(words, tokens, locale) do
    {ordinal, ordinal_position} = find_ordinal(words, tokens)
    weekday_position = position_of_weekday(words, locale)

    compose(%{
      weekday: find_weekday(words, locale),
      month: find_month(words, tokens, locale),
      ordinal: ordinal,
      # Whether the ordinal names a position or a day of the month comes down
      # to where it sits. `4th Thursday` puts it before the weekday and means
      # the fourth one; `Friday the 13th` puts it after and means the 13th day.
      trailing?: !!(ordinal && weekday_position && ordinal_position > weekday_position),
      weekdays?: weekday?(words)
    })
  end

  # `every Friday the 13th` — day 13 of each month, kept only when it is a
  # Friday. `BYDAY` filters rather than selects once `BYMONTHDAY` is present.
  defp compose(%{weekday: weekday, ordinal: day, trailing?: true})
       when is_binary(weekday) and is_integer(day) do
    {:ok, "FREQ=MONTHLY;BYMONTHDAY=#{day};BYDAY=#{weekday}"}
  end

  # `4th Thursday of November` — Thanksgiving, as a rule.
  defp compose(%{weekday: weekday, month: month, ordinal: ordinal})
       when is_binary(weekday) and is_integer(month) and is_integer(ordinal) do
    {:ok, "FREQ=YEARLY;BYMONTH=#{month};BYDAY=#{ordinal}#{weekday}"}
  end

  # `last weekday of every month` — every weekday expanded, then the last.
  defp compose(%{ordinal: ordinal, weekdays?: true}) when is_integer(ordinal) do
    {:ok, "FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=#{ordinal}"}
  end

  defp compose(%{weekday: weekday, ordinal: ordinal})
       when is_binary(weekday) and is_integer(ordinal) do
    {:ok, "FREQ=MONTHLY;BYDAY=#{ordinal}#{weekday}"}
  end

  defp compose(%{weekday: weekday}) when is_binary(weekday) do
    {:ok, "FREQ=WEEKLY;BYDAY=#{weekday}"}
  end

  defp compose(_facts), do: :error

  # An ordinal may be spelled (`fourth`) or written (`4th`), and its position
  # in the line decides what it means.
  defp find_ordinal(words, tokens) do
    spelled =
      words
      |> Enum.with_index()
      |> Enum.find_value(fn {word, index} ->
        case Map.fetch(@ordinals, word) do
          {:ok, value} -> {value, index}
          :error -> nil
        end
      end)

    written =
      tokens
      |> Enum.with_index()
      |> Enum.find_value(fn {token, index} ->
        if token.kind == :ordinal, do: {token.value, index}
      end)

    spelled || written || {nil, nil}
  end

  defp position_of_weekday(words, locale) do
    names = names_for(locale, :days)

    words
    |> Enum.with_index()
    |> Enum.find_value(fn {word, index} ->
      if Map.has_key?(names, strip_ordinal_suffix(word)), do: index
    end)
  end

  defp weekday?(words), do: "weekday" in words or "weekdays" in words

  # A stated year bounds the rule to that year; otherwise take a handful.
  defp bound(rule, _words, tokens) do
    case find_year(tokens) do
      nil -> "#{rule};COUNT=#{@default_count}"
      year -> "#{rule};UNTIL=#{year}-12-31"
    end
  end

  defp start_date(tokens, options) do
    reference = Keyword.get_lazy(options, :reference_date, &Date.utc_today/0)

    case find_year(tokens) do
      nil -> reference
      year -> Date.new!(year, 1, 1)
    end
  end

  # A four-digit number is a year. A one- or two-digit one is a day of the
  # month — `Friday the 13th`.
  defp find_year(tokens) do
    Enum.find_value(tokens, fn token ->
      if token.kind == :number and is_integer(token.value) and token.value > 1900 do
        token.value
      end
    end)
  end

  defp find_weekday(words, locale) do
    names = names_for(locale, :days)

    Enum.find_value(words, fn word ->
      case Map.fetch(names, strip_ordinal_suffix(word)) do
        {:ok, index} -> Map.fetch!(@weekday_codes, index)
        :error -> nil
      end
    end)
  end

  # A month name may survive as a word, or may already have been claimed by the
  # date scanner — `November` on its own parses as a date. Look in both places.
  defp find_month(words, tokens, locale) do
    names = names_for(locale, :months)

    Enum.find_value(words, &Map.get(names, strip_ordinal_suffix(&1))) ||
      Enum.find_value(tokens, fn token ->
        if token.kind == :temporal and is_map(token.value), do: Map.get(token.value, :month)
      end)
  end

  # `13th` arrives as a word when the number scanner has already taken the
  # digits, so a trailing ordinal suffix must not defeat a name lookup.
  defp strip_ordinal_suffix(word), do: String.replace(word, ~r/(st|nd|rd|th)$/u, "")

  # Name-to-index maps built from CLDR, so recurrence vocabulary is localized
  # without a word of it being written here.
  defp names_for(locale, kind) do
    key = {__MODULE__, kind, locale}

    case :persistent_term.get(key, nil) do
      nil ->
        names = build_names(locale, kind)
        :persistent_term.put(key, names)
        names

      names ->
        names
    end
  end

  defp build_names(locale, kind) do
    result =
      if kind == :days, do: Localize.Calendar.days(locale), else: Localize.Calendar.months(locale)

    case result do
      {:ok, %{format: format}} ->
        format
        |> Map.take([:wide, :abbreviated])
        |> Map.values()
        |> Enum.flat_map(&Enum.map(&1, fn {index, name} -> {String.downcase(name), index} end))
        |> Map.new()

      _other ->
        %{}
    end
  end

  @doc """
  Materialises a recurrence into the dates it names.

  ### Arguments

  * `rule` - an RFC 5545 rule string.

  * `from` - the date to start searching at.

  ### Returns

  * `{:ok, interval_set}` on success, or `{:error, reason}`.

  """
  @spec occurrences(String.t(), Date.t()) :: {:ok, Tempo.IntervalSet.t()} | {:error, term()}
  def occurrences(rule, %Date{} = from) do
    recurrence = Tempo.RRule.parse!(rule, from: Tempo.from_elixir(from))

    case Tempo.to_interval(recurrence) do
      {:ok, set} -> {:ok, set}
      {:error, reason} -> {:error, reason}
    end
  rescue
    # A rule the library rejects must show no answer, not take the sheet down.
    exception -> {:error, exception}
  end
end
