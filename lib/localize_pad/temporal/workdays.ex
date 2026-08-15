defmodule LocalizePad.Temporal.Workdays do
  @moduledoc """
  Working-day arithmetic, using the working week of the reader's own territory.

  ## The localization point, made temporally

  Soulver defines a workday as Monday to Friday. That is true in most of the
  world and wrong in a great deal of it: Saudi Arabia works Sunday to Thursday,
  Iran Saturday to Wednesday. CLDR knows every territory's working week, Tempo
  reads it, and the territory comes from the sheet's own locale — so
  `is Friday a workday` answers *yes* for a reader in `en-US` and *no* for one
  in `ar-SA`, with nothing configured.

  This is the clearest single case of the two halves of the product being the
  same thing: a temporal feature that is only correct because it is localized.

  ## Phrases

      December 24, 2026 + 2 workdays        the date, skipping weekends
      workdays from April 12 to June 15     how many there are between
      is Friday a workday                   yes or no
      day of the week on January 24, 1984   the weekday's name

  ## What is not here yet

  Public holidays. Tempo reads them from an `.ics` feed and its holidays guide
  routes officeholidays.com through the same import used for calendars, but
  that is a network dependency and a cache, and it belongs with the `.ics` work
  rather than smuggled in here. Until then a workday is a non-weekend day.

  """

  alias LocalizePad.Token

  @markers ~w(workday workdays weekday weekdays)
  @business ~w(business)

  @type node_type :: {:workdays, atom(), map()}

  @doc """
  Recognises a workday phrase.

  ### Arguments

  * `tokens` - the tokens for one line.

  * `options` - a keyword list of options.

  ### Options

  * `:locale` - the locale whose territory supplies the working week.
    Defaults to `Localize.get_locale/0`.

  ### Returns

  * `{:ok, {:workdays, kind, slots}}` when the line asks a workday question.

  * `:error` otherwise.

  """
  @spec match([Token.t()], keyword()) :: {:ok, node_type()} | :error
  def match(tokens, options \\ []) when is_list(tokens) do
    locale = Keyword.get_lazy(options, :locale, &Localize.get_locale/0)
    words = Enum.map(tokens, &String.downcase(&1.source))
    dates = Enum.filter(tokens, &(&1.kind == :temporal))

    cond do
      names_weekday_question?(words) and dates != [] ->
        {:ok,
         {:workdays, :day_of_week,
          %{date: hd(dates).value, territory: territory(locale), locale: locale}}}

      not mentions_workdays?(words) ->
        :error

      true ->
        build(words, tokens, dates, territory(locale), locale)
    end
  end

  defp build(words, tokens, dates, territory, locale) do
    count = find_count(tokens)

    cond do
      # `workdays from April 12 to June 15` — how many there are between.
      length(dates) >= 2 ->
        {:ok,
         {:workdays, :between,
          %{
            from: hd(dates).value,
            to: dates |> Enum.at(1) |> Map.fetch!(:value),
            territory: territory,
            locale: locale
          }}}

      # `December 24 + 2 workdays` — the date that many working days on.
      dates != [] and count ->
        {:ok,
         {:workdays, :shift,
          %{
            date: hd(dates).value,
            count: signed(count, words),
            territory: territory,
            locale: locale
          }}}

      # `is Friday a workday` — yes or no.
      dates != [] ->
        {:ok,
         {:workdays, :workday?, %{date: hd(dates).value, territory: territory, locale: locale}}}

      true ->
        :error
    end
  end

  # `2 workdays before` counts backwards.
  defp signed(count, words) do
    if "before" in words or "ago" in words, do: -count, else: count
  end

  defp mentions_workdays?(words) do
    Enum.any?(words, &(&1 in @markers)) or Enum.any?(words, &(&1 in @business))
  end

  defp names_weekday_question?(words) do
    ("day" in words and "week" in words) or
      (("weekday" in words or "weekdays" in words) and "on" in words)
  end

  defp find_count(tokens) do
    Enum.find_value(tokens, fn token ->
      if token.kind in [:number, :ordinal] and is_integer(token.value), do: token.value
    end)
  end

  # The working week follows the reader, not the author of this file.
  defp territory(locale) do
    case Localize.Territory.territory_from_locale(locale) do
      {:ok, territory} -> territory
      _other -> :"001"
    end
  end

  @doc """
  Evaluates a matched workday phrase.

  ### Arguments

  * `kind` - the question, from `match/2`.

  * `slots` - the dates, count and territory.

  ### Returns

  * `{:ok, value}` — a `Tempo` date, an integer count, a boolean, or a
    localized weekday name.

  * `{:error, reason}` when the dates cannot be resolved.

  """
  @spec evaluate(atom(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  def evaluate(kind, slots, options \\ [])

  def evaluate(:shift, slots, options) do
    with {:ok, date} <- resolve(slots.date, options) do
      {:ok, Tempo.add_working_days(date, slots.count, slots.territory)}
    end
  end

  def evaluate(:between, slots, options) do
    with {:ok, from} <- resolve(slots.from, options),
         {:ok, to} <- resolve(slots.to, options),
         {:ok, interval} <- Tempo.Interval.new(from: from, to: to) do
      {:ok, Tempo.working_days_in(interval, slots.territory)}
    end
  end

  def evaluate(:workday?, slots, options) do
    with {:ok, date} <- resolve(slots.date, options) do
      {:ok, Tempo.workday?(date, slots.territory)}
    end
  end

  def evaluate(:day_of_week, slots, options) do
    with {:ok, tempo} <- resolve(slots.date, options),
         {:ok, date} <- Tempo.to_date(tempo) do
      Localize.Calendar.localize(date, :day_of_week, locale: slots.locale)
    end
  end

  defp resolve(fields, options) do
    LocalizePad.Temporal.resolve(fields, Keyword.take(options, [:reference_date]))
  end
end
