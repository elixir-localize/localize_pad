defmodule LocalizePad.Timeline do
  @moduledoc """
  Laying a temporal answer out on an axis, so its shape can be seen rather than
  read.

  ## What a list of dates does not tell you

  `every Friday the 13th in 2027` answers with one date. `every Monday` answers
  with five, evenly spaced. `every last Friday of the quarter` answers with
  four, clustered in threes-apart clumps. Read as a list those look alike — a
  row of medium-format dates — and the reader has to do the arithmetic to
  notice that one is regular and one is lumpy.

  Drawn on a common axis the difference is immediate, and it is usually the
  thing the question was actually about: *when am I free*, *do these overlap*,
  *how long is the gap*.

  ## The axis is snapped, not padded

  A naive axis runs from the first mark to the last, which puts both hard
  against the edges and makes the tick labels land on arbitrary instants. This
  one is rounded outwards to whole units — to the hour, the day, the month, the
  year — which produces clean labels and honest breathing room at both ends
  from the same decision.

  The step is chosen so an axis carries somewhere between three and eight
  ticks, whatever its length. A day-long window gets hours; a year of quarterly
  meetings gets months.

  ## An axis has one clock

  The overlap of London's working day and New York's is a single span whose two
  ends sit in different zones — it begins at 9am in New York and ends at 5pm in
  London. Both instants are correct, and drawing each against its own clock
  makes a three-hour overlap read as eight.

  So every instant is shifted into one zone before any label is written, and
  `:zone` says which. The positions never needed it — they are computed from
  instants, which have no zone — but the labels are the part anyone reads.

  ## Fractions, not pixels

  Marks carry their position and width as fractions of the axis. The layout
  layer decides how wide the axis is, and a zero-length mark — a point in time
  rather than a span — stays zero-length here rather than being quietly widened
  to something visible. Making a point big enough to see is a rendering
  decision, and it belongs where the pixels are.

  """

  alias LocalizePad.Temporal.Window

  defmodule Mark do
    @moduledoc """
    One occurrence on a timeline, positioned as a fraction of the axis.

    """

    defstruct [:start, :width, :label]

    @type t :: %__MODULE__{start: float(), width: float(), label: String.t()}
  end

  defmodule Tick do
    @moduledoc """
    One labelled division of a timeline's axis.

    """

    defstruct [:at, :label]

    @type t :: %__MODULE__{at: float(), label: String.t()}
  end

  defstruct [:from, :to, :marks, :ticks, :unit, :zone]

  @type t :: %__MODULE__{
          from: DateTime.t(),
          to: DateTime.t(),
          marks: [Mark.t()],
          ticks: [Tick.t()],
          unit: :hour | :day | :month | :year,
          zone: String.t()
        }

  # Smallest step first. A step is chosen by walking this until one of them
  # divides the span into at most `@maximum_ticks` pieces, so the ladder's
  # order is the algorithm and not merely documentation.
  @steps [
    {:hour, 1},
    {:hour, 3},
    {:hour, 6},
    {:day, 1},
    {:day, 7},
    {:month, 1},
    {:month, 3},
    {:year, 1},
    {:year, 5},
    {:year, 10}
  ]

  @maximum_ticks 8
  @seconds_per_day 86_400

  @doc """
  Lays a temporal value out on an axis.

  ### Arguments

  * `value` - an evaluated value. Recurrence sets, windows, dates and instants
    can be drawn; everything else cannot.

  * `options` - a keyword list of options.

  ### Options

  * `:locale` - the locale the tick and mark labels are written in. Defaults to
    `Localize.get_locale/0`.

  ### Returns

  * `{:ok, timeline}` when the value has a position in time.

  * `:error` when it does not. A number or a sum has no place on an axis, and
    that is the common case rather than a failure — callers draw nothing.

  ### Examples

      iex> {:ok, window} =
      ...>   LocalizePad.Temporal.Window.new(~T[09:00:00], ~T[17:00:00], date: ~D[2026-06-15])
      iex> {:ok, timeline} = LocalizePad.Timeline.build(window, locale: :en)
      iex> timeline.unit
      :hour
      iex> length(timeline.marks)
      1

      iex> LocalizePad.Timeline.build(42, locale: :en)
      :error

  """
  @spec build(term(), keyword()) :: {:ok, t()} | :error
  def build(value, options \\ []) do
    locale = Keyword.get_lazy(options, :locale, &Localize.get_locale/0)

    with {:ok, spans} <- spans(value),
         [_at_least_one | _] <- spans do
      {:ok, assemble(spans, locale)}
    else
      _not_temporal -> :error
    end
  end

  # Every drawable value reduces to a list of `{from, to}` instants. Doing that
  # first is what lets the axis, the ticks and the marks be written once rather
  # than once per temporal type.
  defp spans(%Tempo.IntervalSet{} = set) do
    spans =
      set
      |> Tempo.IntervalSet.to_list()
      |> Enum.map(&interval_span/1)
      |> Enum.reject(&is_nil/1)

    {:ok, spans}
  end

  defp spans(%Window{from: %DateTime{} = from, to: %DateTime{} = to}) do
    {:ok, [{from, to}]}
  end

  defp spans(%DateTime{} = at), do: {:ok, [{at, at}]}

  defp spans(%Date{} = date) do
    with {:ok, from} <- midnight(date) do
      {:ok, [{from, DateTime.add(from, @seconds_per_day, :second)}]}
    end
  end

  defp spans(%Tempo{} = tempo) do
    with {:ok, date} <- Tempo.to_date(tempo) do
      spans(date)
    end
  end

  defp spans(_other), do: :error

  defp interval_span(interval) do
    with {:ok, from} <- tempo_instant(Tempo.Interval.from(interval)),
         {:ok, to} <- tempo_instant(Tempo.Interval.to(interval)) do
      {from, to}
    else
      _unresolvable -> nil
    end
  end

  defp tempo_instant(%Tempo{} = tempo) do
    with {:ok, date} <- Tempo.to_date(tempo) do
      midnight(date)
    end
  end

  defp tempo_instant(_other), do: :error

  defp midnight(%Date{} = date) do
    with {:ok, naive} <- NaiveDateTime.new(date, ~T[00:00:00]) do
      DateTime.from_naive(naive, "Etc/UTC")
    end
  end

  defp assemble(unzoned, locale) do
    zone = zone_of(unzoned)
    spans = Enum.map(unzoned, fn {from, to} -> {shift(from, zone), shift(to, zone)} end)

    earliest = spans |> Enum.map(&elem(&1, 0)) |> Enum.min(DateTime)
    latest = spans |> Enum.map(&elem(&1, 1)) |> Enum.max(DateTime)

    {unit, step} = step_for(DateTime.diff(latest, earliest, :second), granularity(spans))
    {from, to} = axis(earliest, latest, unit, step)
    seconds = max(DateTime.diff(to, from, :second), 1)

    %__MODULE__{
      from: from,
      to: to,
      unit: unit,
      zone: zone,
      marks: Enum.map(spans, &mark(&1, from, seconds, unit, locale)),
      ticks: ticks(from, to, seconds, unit, step, locale)
    }
  end

  # The overlap of London's working day and New York's is one span whose ends
  # sit in different zones — 9am in New York, 5pm in London. Both instants are
  # right, and labelling each in its own clock makes a three-hour overlap read
  # as eight. An axis has one clock, and the earliest instant's zone is it.
  defp zone_of(spans) do
    spans
    |> Enum.map(&elem(&1, 0))
    |> Enum.min(DateTime)
    |> Map.get(:time_zone)
  end

  defp shift(at, zone) do
    case DateTime.shift_zone(at, zone) do
      {:ok, shifted} -> shifted
      _no_such_zone -> at
    end
  end

  # A single instant has a zero-second span, which no step divides into more
  # than zero pieces, so the smallest allowed step wins and the axis becomes
  # the hour around it. That is the right answer for `3pm in Tokyo`.
  defp step_for(seconds, granularity) do
    @steps
    |> Enum.drop_while(fn {unit, _step} -> unit == :hour and granularity == :day end)
    |> Enum.find(List.last(@steps), fn {unit, step} ->
      seconds / (step * unit_seconds(unit)) <= @maximum_ticks
    end)
  end

  # A set of whole days carries no time of day, so an hour axis would invent
  # precision the answer does not have — `every Friday the 13th` would be drawn
  # against a clock and its one mark labelled "12:00 AM".
  defp granularity(spans) do
    if Enum.all?(spans, fn {from, to} -> midnight?(from) and midnight?(to) end) do
      :day
    else
      :hour
    end
  end

  defp midnight?(at) do
    at.hour == 0 and at.minute == 0 and at.second == 0
  end

  # Two ticks describe a length but not a position: a lone date snapped to its
  # own day fills the axis end to end and says only "somewhere in here". One
  # step of context on each side puts the mark back in the middle of something.
  defp axis(earliest, latest, unit, step) do
    from = floor_to(earliest, unit, step)
    to = ceiling_to(latest, unit, step)

    if DateTime.diff(to, from, :second) <= step * unit_seconds(unit) do
      {advance(from, unit, -step), advance(to, unit, step)}
    else
      {from, to}
    end
  end

  defp unit_seconds(:hour), do: 3600
  defp unit_seconds(:day), do: @seconds_per_day
  defp unit_seconds(:month), do: 2_629_800
  defp unit_seconds(:year), do: 31_557_600

  defp mark({from, to}, axis_from, seconds, unit, locale) do
    %Mark{
      start: DateTime.diff(from, axis_from, :second) / seconds,
      width: max(DateTime.diff(to, from, :second), 0) / seconds,
      label: mark_label(from, to, unit, locale)
    }
  end

  # An hour-scale axis is a day being examined, so its marks are clock times. A
  # coarser one is a run of days, where the time of day is noise.
  defp mark_label(from, to, :hour, locale) do
    joined =
      [from, to]
      |> Enum.map(&format(DateTime.to_time(&1), :time, :short, locale))
      |> Enum.uniq()
      |> Enum.join(" – ")

    joined
  end

  defp mark_label(from, _to, _unit, locale) do
    format(DateTime.to_date(from), :date, :medium, locale)
  end

  defp ticks(from, to, seconds, unit, step, locale) do
    from
    |> Stream.iterate(&advance(&1, unit, step))
    |> Stream.take_while(&(DateTime.compare(&1, to) != :gt))
    |> Stream.take(@maximum_ticks + 1)
    |> Enum.map(fn at ->
      %Tick{
        at: DateTime.diff(at, from, :second) / seconds,
        label: tick_label(at, unit, locale)
      }
    end)
  end

  defp tick_label(at, :hour, locale) do
    format(DateTime.to_time(at), :time, :short, locale)
  end

  defp tick_label(at, :day, locale) do
    format(DateTime.to_date(at), :date, :MMMd, locale)
  end

  defp tick_label(at, :month, locale) do
    format(DateTime.to_date(at), :date, :MMM, locale)
  end

  defp tick_label(at, :year, locale) do
    format(DateTime.to_date(at), :date, :y, locale)
  end

  # A label that cannot be produced in the requested locale falls back rather
  # than taking the panel down with it. ISO is nobody's preference, but it is
  # unambiguous in every locale, which is the property that matters in a
  # fallback.
  defp format(value, type, format, locale) do
    case formatted(value, type, format, locale) do
      {:ok, string} -> string
      _other -> iso(value)
    end
  end

  defp formatted(value, :date, format, locale) do
    Localize.Date.to_string(value, locale: locale, format: format)
  end

  defp formatted(value, :time, format, locale) do
    Localize.Time.to_string(value, locale: locale, format: format)
  end

  defp iso(%Date{} = date), do: Date.to_iso8601(date)
  defp iso(%Time{} = time), do: Time.to_iso8601(time)

  defp advance(at, :hour, step), do: DateTime.add(at, step * 3600, :second)
  defp advance(at, :day, step), do: DateTime.add(at, step * @seconds_per_day, :second)

  defp advance(at, :month, step) do
    at
    |> DateTime.to_date()
    |> Date.shift(month: step)
    |> rebuild(at)
  end

  defp advance(at, :year, step) do
    at
    |> DateTime.to_date()
    |> Date.shift(year: step)
    |> rebuild(at)
  end

  defp rebuild(date, template) do
    case midnight(date) do
      {:ok, at} -> at
      _other -> DateTime.add(template, @seconds_per_day, :second)
    end
  end

  defp floor_to(at, :hour, step) do
    %{at | minute: 0, second: 0, microsecond: {0, 0}, hour: at.hour - Integer.mod(at.hour, step)}
  end

  defp floor_to(at, :day, _step), do: %{at | hour: 0, minute: 0, second: 0, microsecond: {0, 0}}

  defp floor_to(at, :month, _step) do
    at |> floor_to(:day, 1) |> Map.put(:day, 1)
  end

  defp floor_to(at, :year, step) do
    at
    |> floor_to(:month, 1)
    |> Map.merge(%{month: 1, year: at.year - Integer.mod(at.year, step)})
  end

  # The ceiling is a floor plus one step, except when the value already sits
  # exactly on a boundary — extending then would leave a whole empty step
  # hanging off the end of the axis.
  defp ceiling_to(at, unit, step) do
    floored = floor_to(at, unit, step)

    if DateTime.compare(floored, at) == :eq do
      floored
    else
      advance(floored, unit, step)
    end
  end
end
