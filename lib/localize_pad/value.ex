defmodule LocalizePad.Value do
  @moduledoc """
  Renders an evaluated value for the answer column.

  Formatting is the second half of the localization story. The tokenizer reads
  `1.234,5` correctly under `:de` because CLDR says what the separators are;
  this module writes the answer back out under the same rules, so a sheet's
  input and output agree about what a number looks like.

  Everything here delegates to `Localize` — `Localize.Number.to_string/2` for
  bare numbers and `Localize.Unit.to_string/2` for quantities, the latter of
  which also handles unit pluralisation and the locale's own unit display
  names.

  """

  alias Localize.Unit

  # Answers are rounded for display while the underlying value keeps full
  # precision, because float conversion produces things like
  # 211.99999999999997 that nobody wants to read. Six digits matches Unity and
  # is enough for every unit conversion in practice.
  @default_maximum_fractional_digits 6

  # How many occurrences of a recurring answer fit in a margin before the list
  # stops being readable.
  @summary_limit 4

  @doc """
  Formats a value as a localized string.

  ### Arguments

  * `value` - a number or a `t:Localize.Unit.t/0`.

  * `options` - a keyword list of options.

  ### Options

  * `:locale` - the locale to format in. Defaults to `Localize.get_locale/0`.

  * `:maximum_fractional_digits` - how many fractional digits to show.
    Defaults to `6`.

  ### Returns

  * `{:ok, string}` on success.

  * `{:error, reason}` when the value cannot be formatted.

  ### Examples

      iex> LocalizePad.Value.format(1234.5, locale: :en)
      {:ok, "1,234.5"}

      iex> LocalizePad.Value.format(1234.5, locale: :de)
      {:ok, "1.234,5"}

      iex> {:ok, unit} = Localize.Unit.new(3, "meter")
      iex> LocalizePad.Value.format(unit, locale: :en)
      {:ok, "3 meters"}

  """
  @spec format(LocalizePad.Evaluator.value(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def format(value, options \\ [])

  def format(%Unit{} = unit, options) do
    Unit.to_string(unit, format_options(options))
  end

  def format(number, options) when is_number(number) do
    Localize.Number.to_string(number, format_options(options))
  end

  # A zoned answer is shown as a clock time. The question `6pm Sydney in
  # Chicago` asks what the clock reads there, so the date would be noise —
  # except when it differs from the source date, which is exactly when it
  # matters most.
  def format(%DateTime{} = datetime, options) do
    Localize.Time.to_string(DateTime.to_time(datetime),
      locale: locale_of(options),
      format: :short
    )
  end

  # A recurrence has no single answer, so the margin gets a summary and the
  # dates themselves. Both are shown because "2 dates" alone answers nothing,
  # and a bare list stops being readable past a handful — this is the
  # collapsed-summary half of the set-answer design, with the expansion panel
  # still to come.
  def format(%Tempo.IntervalSet{} = set, options) do
    locale = locale_of(options)
    dates = set |> Tempo.IntervalSet.to_list() |> Enum.map(&Tempo.Interval.from/1)

    formatted =
      dates
      |> Enum.take(@summary_limit)
      |> Enum.map(&format_occurrence(&1, locale))
      |> Enum.reject(&is_nil/1)

    {:ok, summarise(formatted, length(dates), locale)}
  end

  # `is Friday a workday` deserves a word, not `true`. Not yet a translated
  # message — the answer vocabulary arrives with the operator lexicon in M6.
  def format(true, _options), do: {:ok, "yes"}
  def format(false, _options), do: {:ok, "no"}

  # Some answers are words rather than quantities — a weekday's name, and
  # later an explanation of how a value was read. They are already localized
  # by whatever produced them.
  def format(text, _options) when is_binary(text), do: {:ok, text}

  def format(%LocalizePad.Temporal.Window{} = window, options) do
    LocalizePad.Temporal.Window.format(window, options)
  end

  def format(%LocalizePad.Rate{} = rate, options) do
    LocalizePad.Rate.format(rate, options)
  end

  def format(%Money{} = money, options) do
    Money.to_string(money, locale: locale_of(options))
  end

  def format(%LocalizePad.Percentage{} = percentage, options) do
    LocalizePad.Percentage.format(percentage, options)
  end

  def format(%Localize.Duration{} = duration, options) do
    Localize.Duration.to_string(duration, locale: locale_of(options))
  end

  def format(%module{} = temporal, options) when module in [Tempo, Tempo.Duration] do
    LocalizePad.Temporal.format(temporal, options)
  end

  def format(other, _options) do
    {:error, {:unformattable, other}}
  end

  @doc """
  Describes the kind of a value, for display and for deciding what operations
  apply.

  ### Arguments

  * `value` - any evaluated value.

  ### Returns

  * An atom naming the kind: `:number`, `:quantity`, `:temporal`, `:duration`,
    `:zoned_time`, `:percentage` or `:unknown`.

  ### Examples

      iex> LocalizePad.Value.kind(42)
      :number

      iex> {:ok, unit} = Localize.Unit.new(3, "meter")
      iex> LocalizePad.Value.kind(unit)
      :quantity

  """
  @spec kind(term()) ::
          :number
          | :quantity
          | :temporal
          | :duration
          | :zoned_time
          | :percentage
          | :money
          | :rate
          | :temporal_set
          | :window
          | :boolean
          | :text
          | :unknown
  def kind(%Unit{}), do: :quantity
  def kind(%Tempo{}), do: :temporal
  def kind(%Tempo.Duration{}), do: :duration
  def kind(%Localize.Duration{}), do: :duration
  def kind(%DateTime{}), do: :zoned_time
  def kind(%LocalizePad.Percentage{}), do: :percentage
  def kind(%Money{}), do: :money
  def kind(%LocalizePad.Rate{}), do: :rate
  def kind(%Tempo.IntervalSet{}), do: :temporal_set
  def kind(%LocalizePad.Temporal.Window{}), do: :window
  def kind(value) when is_boolean(value), do: :boolean
  def kind(value) when is_binary(value), do: :text
  def kind(value) when is_number(value), do: :number
  def kind(_other), do: :unknown

  # Localize spells the option `:max_fractional_digits`; this module's own
  # option follows the house convention of complete words, so translate at the
  # boundary rather than leaking the abbreviation into the public API.
  defp format_occurrence(tempo, locale) do
    with {:ok, date} <- Tempo.to_date(tempo),
         {:ok, formatted} <- Localize.Date.to_string(date, locale: locale, format: :medium) do
      formatted
    else
      _other -> nil
    end
  end

  defp summarise([], _count, _locale), do: ""

  # The count goes first when the list is cut short. A margin truncates from
  # the right, so "5 dates · Nov 13 …" still says how many there are while
  # "Nov 13, Aug 13, Oct 13 …" loses the only part that was not visible anyway.
  defp summarise(formatted, count, locale) do
    listed = Enum.join(formatted, ", ")

    if count > length(formatted) do
      {:ok, total} = Localize.Number.to_string(count, locale: locale)
      "#{total} dates · #{listed} …"
    else
      listed
    end
  end

  defp locale_of(options) do
    Keyword.get_lazy(options, :locale, &Localize.get_locale/0)
  end

  defp format_options(options) do
    maximum =
      Keyword.get(options, :maximum_fractional_digits, @default_maximum_fractional_digits)

    [locale: locale_of(options), max_fractional_digits: maximum]
  end
end
