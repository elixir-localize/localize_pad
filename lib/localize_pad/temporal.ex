defmodule LocalizePad.Temporal do
  @moduledoc """
  Turns the field maps produced by `LocalizePad.Temporal.Scanner` into `Tempo`
  values, and renders them back out in the sheet's locale.

  ## Why Tempo rather than `Date`

  A notepad has to hold `10 June` (a day with no year), `7:45am` (a time with
  no date), `Q2 2026` (a span of three months) and `2026-06-15T14:30` in the
  same column, and then do arithmetic across them. `Tempo` is one type at any
  resolution, which is exactly that shape; assembling the same behaviour from
  `Date`, `Time`, `NaiveDateTime` and a home-made "which fields are set" flag
  is the thing Tempo exists to avoid.

  ## The missing year

  `10 June` has no year, and the reasonable reading depends on when you are
  reading it. Soulver's rule — and this module's — is *nearest*: in December,
  `January 12` means next January rather than the one ten months gone; in
  early December, `November 1` means five weeks ago rather than eleven months
  hence.

  The reference date is an option so this is testable rather than dependent on
  the day the suite happens to run.

  """

  @type fields :: map()

  # Field names `Calendrical` produces that map straight onto Tempo
  # components, in coarse-to-fine order.
  @components [:year, :month, :day, :hour, :minute, :second]

  @doc """
  Resolves a partial field map into a `Tempo` value.

  ### Arguments

  * `fields` - the map from `Calendrical.parse/2` with `as: :map`.

  * `options` - a keyword list of options.

  ### Options

  * `:reference_date` - the date from which "nearest" is measured when the
    year is missing. Defaults to `Date.utc_today/0`.

  ### Returns

  * `{:ok, tempo}` on success.

  * `{:error, reason}` when the fields describe something not yet supported —
    a quarter, for instance, which is a span rather than an instant and
    arrives with the interval work.

  ### Examples

      iex> {:ok, tempo} =
      ...>   LocalizePad.Temporal.resolve(%{year: 2026, month: 6, day: 15})
      iex> Tempo.to_date(tempo)
      {:ok, ~D[2026-06-15]}

      iex> {:ok, tempo} =
      ...>   LocalizePad.Temporal.resolve(%{hour: 7, minute: 45})
      iex> Tempo.hour(tempo)
      7

  """
  @spec resolve(fields() | {:deictic, atom()}, keyword()) :: {:ok, Tempo.t()} | {:error, term()}
  def resolve(fields, options \\ [])

  # `today` and its neighbours are resolved against the reference date rather
  # than being parsed, since there is nothing in them to parse.
  def resolve({:deictic, moment}, options) do
    reference = Keyword.get_lazy(options, :reference_date, &Date.utc_today/0)

    case moment do
      :today -> from_date(reference)
      :tomorrow -> reference |> Date.add(1) |> from_date()
      :yesterday -> reference |> Date.add(-1) |> from_date()
      :now -> from_datetime(Keyword.get_lazy(options, :reference_datetime, &DateTime.utc_now/0))
    end
  end

  def resolve(fields, options) when is_map(fields) do
    reference = Keyword.get_lazy(options, :reference_date, &Date.utc_today/0)

    cond do
      Map.has_key?(fields, :quarter) ->
        {:error, {:unsupported_temporal, :quarter}}

      Map.has_key?(fields, :week) ->
        {:error, {:unsupported_temporal, :week}}

      true ->
        with {:ok, tempo} <- fields |> supply_year(reference) |> to_components() |> build() do
          apply_parsed_zone(tempo, Map.get(fields, :time_zone), options)
        end
    end
  end

  # `Calendrical.parse/2` captures a trailing zone string — `7:30am LAX` yields
  # `%{hour: 7, minute: 30, time_zone: "LAX"}` — but leaves it unresolved,
  # since what counts as a zone name is the caller's business. Resolving it
  # here means abbreviations, IANA names and airport codes all arrive by the
  # same route as a city typed on its own.
  defp apply_parsed_zone(tempo, nil, _options), do: {:ok, tempo}

  defp apply_parsed_zone(tempo, zone_string, options) do
    case LocalizePad.Temporal.Zones.resolve(zone_string) do
      {:ok, zone} -> in_zone(tempo, zone, options)
      # An unrecognised zone leaves the time as a plain wall-clock value rather
      # than failing the line — the time is still the time.
      :error -> {:ok, tempo}
    end
  end

  # A date carrying a month but no year is completed with whichever adjacent
  # year puts it closest to the reference date.
  defp supply_year(%{month: month, day: day} = fields, reference)
       when not is_map_key(fields, :year) do
    year =
      [reference.year - 1, reference.year, reference.year + 1]
      |> Enum.filter(&valid_date?(&1, month, day))
      |> Enum.min_by(&distance_from(&1, month, day, reference), fn -> reference.year end)

    Map.put(fields, :year, year)
  end

  defp supply_year(fields, _reference), do: fields

  defp valid_date?(year, month, day) do
    match?({:ok, _date}, Date.new(year, month, day))
  end

  defp distance_from(year, month, day, reference) do
    case Date.new(year, month, day) do
      {:ok, date} -> abs(Date.diff(date, reference))
      {:error, _reason} -> :infinity
    end
  end

  defp to_components(fields) do
    Enum.flat_map(@components, fn component ->
      case Map.fetch(fields, component) do
        {:ok, value} when is_integer(value) -> [{component, value}]
        _other -> []
      end
    end)
  end

  defp from_date(%Date{} = date) do
    Tempo.new(year: date.year, month: date.month, day: date.day)
  end

  defp from_datetime(%DateTime{} = datetime) do
    Tempo.new(
      year: datetime.year,
      month: datetime.month,
      day: datetime.day,
      hour: datetime.hour,
      minute: datetime.minute
    )
  end

  defp build([]), do: {:error, :no_temporal_fields}

  defp build(components) do
    Tempo.new(components)
  rescue
    # Tempo validates against the calendar and is not supposed to raise here,
    # but this is the render path of a live document.
    exception -> {:error, exception}
  end

  @doc """
  Converts a time-dimensioned quantity into a `Tempo.Duration`.

  `3 weeks` reaches the evaluator as an ordinary `Localize.Unit` quantity,
  because the unit engine already knows what a week is. This is the adapter
  that lets such a quantity act on a date.

  ### Arguments

  * `unit` - a `t:Localize.Unit.t/0`.

  ### Returns

  * `{:ok, duration}` when the unit names a calendar component and its value
    is a whole number.

  * `{:error, reason}` otherwise — `3.5 weeks` has no unambiguous calendar
    meaning, and neither does `3 metres`.

  ### Examples

      iex> {:ok, weeks} = Localize.Unit.new(3, "week")
      iex> {:ok, duration} = LocalizePad.Temporal.duration(weeks)
      iex> to_string(duration)
      "21 days"

  """
  @spec duration(Localize.Unit.t()) :: {:ok, Tempo.Duration.t()} | {:error, term()}
  def duration(%Localize.Unit{name: name, value: value}) do
    with {:ok, component} <- calendar_component(name),
         {:ok, whole} <- whole_number(value) do
      Tempo.Duration.new([{component, whole}])
    end
  end

  def duration(other), do: {:error, {:not_a_duration, other}}

  defp calendar_component(name) when name in ~w(year month week day hour minute second) do
    {:ok, String.to_existing_atom(name)}
  end

  defp calendar_component(name), do: {:error, {:not_a_calendar_unit, name}}

  defp whole_number(value) when is_integer(value), do: {:ok, value}

  defp whole_number(value) when is_float(value) do
    if value == Float.round(value) do
      {:ok, trunc(value)}
    else
      {:error, {:fractional_duration, value}}
    end
  end

  defp whole_number(value), do: {:error, {:fractional_duration, value}}

  @doc """
  Converts a time-only value into an Elixir `Time`.

  `Tempo.to_elixir/1` cannot do this: it routes a value carrying only clock
  fields towards `NaiveDateTime` and fails for want of a date. The individual
  field accessors do work, so this assembles the `Time` from those.

  ### Arguments

  * `tempo` - a `Tempo` value.

  ### Returns

  * `{:ok, time}` when the value carries clock fields and no date.

  * `:error` otherwise — including for a full datetime, which has a date and
    should be treated as one.

  ### Examples

      iex> {:ok, tempo} = LocalizePad.Temporal.resolve(%{hour: 7, minute: 30})
      iex> LocalizePad.Temporal.to_time(tempo)
      {:ok, ~T[07:30:00]}

      iex> {:ok, tempo} = LocalizePad.Temporal.resolve(%{year: 2026, month: 6, day: 15})
      iex> LocalizePad.Temporal.to_time(tempo)
      :error

  """
  @spec to_time(Tempo.t()) :: {:ok, Time.t()} | :error
  def to_time(%Tempo{} = tempo) do
    hour = Tempo.hour(tempo)

    if is_integer(hour) and is_nil(Tempo.year(tempo)) do
      # `Time.new/3` reports its own error shape; this function's contract is
      # the simpler `{:ok, time} | :error`, so narrow it here.
      case Time.new(hour, Tempo.minute(tempo) || 0, Tempo.second(tempo) || 0) do
        {:ok, time} -> {:ok, time}
        {:error, _reason} -> :error
      end
    else
      :error
    end
  end

  def to_time(_other), do: :error

  @doc """
  Anchors a temporal value to a time zone, producing a `DateTime`.

  `6pm Sydney` is a wall-clock time and a place. Turning it into an instant
  needs a date as well, and a bare time has none — so today's date supplies
  one. That is the reading a person means: `6pm Sydney` is today's 6pm there,
  not some abstract 6pm.

  ### Arguments

  * `tempo` - the temporal value.

  * `zone` - a `t:LocalizePad.Temporal.Zones.t/0`.

  * `options` - a keyword list of options.

  ### Options

  * `:reference_date` - the date to anchor a bare time to. Defaults to
    `Date.utc_today/0`.

  ### Returns

  * `{:ok, datetime}` on success.

  * `{:error, reason}` when the value carries no clock time, or the zone is
    not in the loaded timezone database.

  """
  @spec in_zone(Tempo.t(), LocalizePad.Temporal.Zones.t(), keyword()) ::
          {:ok, DateTime.t()} | {:error, term()}
  def in_zone(%Tempo{} = tempo, %LocalizePad.Temporal.Zones{name: zone}, options \\ []) do
    reference = Keyword.get_lazy(options, :reference_date, &Date.utc_today/0)

    case to_time(tempo) do
      {:ok, time} -> anchor(tempo, time, zone, reference)
      :error -> {:error, :not_a_clock_time}
    end
  end

  # A wall-clock time on a daylight-saving boundary may name two instants or
  # none. Both are resolved rather than reported, because a notepad answer is
  # better slightly arbitrary than absent: the earlier of an ambiguous pair,
  # and the instant just before a gap.
  defp anchor(tempo, time, zone, reference) do
    case DateTime.new(date_of(tempo, reference), time, zone) do
      {:ok, datetime} -> {:ok, datetime}
      {:ambiguous, first, _second} -> {:ok, first}
      {:gap, just_before, _just_after} -> {:ok, just_before}
      {:error, reason} -> {:error, {:unknown_zone, zone, reason}}
    end
  end

  defp date_of(%Tempo{} = tempo, reference) do
    case Tempo.to_date(tempo) do
      {:ok, date} -> date
      _no_date -> reference
    end
  end

  @doc """
  Formats a temporal value in the given locale.

  ### Arguments

  * `value` - a `Tempo` value or a `Tempo.Duration`.

  * `options` - a keyword list of options.

  ### Options

  * `:locale` - the locale to format in. Defaults to `Localize.get_locale/0`.

  ### Returns

  * `{:ok, string}` on success, or `{:error, reason}`.

  ### Examples

      iex> {:ok, tempo} = LocalizePad.Temporal.resolve(%{year: 2026, month: 6, day: 15})
      iex> LocalizePad.Temporal.format(tempo, locale: :en)
      {:ok, "June 15, 2026"}

      iex> {:ok, tempo} = LocalizePad.Temporal.resolve(%{year: 2026, month: 6, day: 15})
      iex> LocalizePad.Temporal.format(tempo, locale: :de)
      {:ok, "15. Juni 2026"}

  """
  @spec format(Tempo.t() | Tempo.Duration.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def format(value, options \\ [])

  def format(%Tempo.Duration{} = duration, _options) do
    {:ok, to_string(duration)}
  end

  def format(%Tempo{} = tempo, options) do
    locale = Keyword.get_lazy(options, :locale, &Localize.get_locale/0)

    # Render through Localize wherever the value maps onto an Elixir type, so
    # the answer follows the locale's own date and time patterns rather than
    # ISO 8601. A value that has no Elixir equivalent — a masked year, an
    # open-ended interval — falls back to its ISO form, which is at least
    # unambiguous.
    #
    # `to_elixir/1` yields `Date`, `Time`, `NaiveDateTime` or `Duration` and
    # never a `DateTime`, so a zoned value arrives here without its zone.
    # Rendering the offset is part of the timezone work.
    case {to_time(tempo), Tempo.to_elixir(tempo)} do
      {{:ok, time}, _elixir} ->
        Localize.Time.to_string(time, locale: locale, format: :short)

      {_no_time, {:ok, %Date{} = date}} ->
        Localize.Date.to_string(date, locale: locale, format: :long)

      {_no_time, {:ok, %NaiveDateTime{} = naive}} ->
        Localize.DateTime.to_string(naive, locale: locale)

      _other ->
        {:ok, to_string(tempo)}
    end
  end

  def format(other, _options), do: {:error, {:unformattable, other}}
end
