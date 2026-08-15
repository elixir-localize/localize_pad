defmodule LocalizePad.Temporal.Window do
  @moduledoc """
  A span of clock time, optionally pinned to a zone — `9am to 5pm London`.

  ## Why a clock span is an interval, not a duration

  `7:30 to 20:45` displays as "13 hours, 15 minutes", and for a long time that
  was all it needed to be. But the moment two spans are compared —
  *when are London and New York both at work* — the length is useless and the
  endpoints are everything.

  So a clock span is kept as an interval and *renders* as its length. The
  familiar answer is unchanged and the useful one becomes possible.

  ## Wall clock in, instants out

  The endpoints are wall-clock times: `9am to 5pm` means nine in the morning
  wherever you are. Attaching a zone re-reads those same wall-clock readings in
  that zone, which is why `in_zone/2` rebuilds from the fields rather than
  shifting the instants — shifting would turn 9am London into 4am New York
  instead of leaving it as another 9am.

  Comparison then happens on the underlying instants, so an intersection is
  correct across zones without anything here knowing about offsets.

  ## An empty window is a real answer

  Two teams whose working hours do not meet produce an empty window, and that
  is the answer they need. It is distinct from a failure, and renders as such.

  """

  defstruct [:from, :to]

  @type t :: %__MODULE__{from: DateTime.t() | nil, to: DateTime.t() | nil}

  @doc """
  Builds a window from two wall-clock times on a given date.

  ### Arguments

  * `from`, `to` - `t:Time.t/0` endpoints.

  * `options` - a keyword list of options.

  ### Options

  * `:date` - the day to anchor to. Defaults to `Date.utc_today/0`.

  * `:zone` - the IANA zone name. Defaults to `"Etc/UTC"`.

  ### Returns

  * `{:ok, window}` on success, or `{:error, reason}`.

  ### Examples

      iex> {:ok, window} =
      ...>   LocalizePad.Temporal.Window.new(~T[09:00:00], ~T[17:00:00], date: ~D[2026-06-15])
      iex> LocalizePad.Temporal.Window.hours(window)
      8.0

  """
  @spec new(Time.t(), Time.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def new(%Time{} = from, %Time{} = to, options \\ []) do
    date = Keyword.get_lazy(options, :date, &Date.utc_today/0)
    zone = Keyword.get(options, :zone, "Etc/UTC")

    with {:ok, start} <- at(date, from, zone),
         {:ok, finish} <- at(date, to, zone) do
      # A finish earlier on the clock than the start means the following day —
      # `10pm to 6am` is a night shift, not a negative span.
      finish = if DateTime.compare(finish, start) == :lt, do: add_day(finish), else: finish

      {:ok, %__MODULE__{from: start, to: finish}}
    end
  end

  defp at(date, time, zone) do
    case DateTime.new(date, time, zone) do
      {:ok, datetime} -> {:ok, datetime}
      {:ambiguous, first, _second} -> {:ok, first}
      {:gap, just_before, _just_after} -> {:ok, just_before}
      {:error, reason} -> {:error, {:unknown_zone, zone, reason}}
    end
  end

  defp add_day(datetime), do: DateTime.add(datetime, 86_400, :second)

  @doc """
  Re-reads the window's wall-clock times in another zone.

  This is not a shift. `9am to 5pm` moved to New York is still nine to five —
  New York's nine to five.

  ### Arguments

  * `window` - the window to move.

  * `zone` - the IANA zone name.

  ### Returns

  * `{:ok, window}` on success, or `{:error, reason}`.

  """
  @spec in_zone(t(), String.t()) :: {:ok, t()} | {:error, term()}
  def in_zone(%__MODULE__{from: from, to: to}, zone) when is_binary(zone) do
    new(DateTime.to_time(from), DateTime.to_time(to),
      date: DateTime.to_date(from),
      zone: zone
    )
  end

  @doc """
  The part two windows have in common.

  ### Arguments

  * `left`, `right` - the windows to intersect.

  ### Returns

  * A window. When the two do not meet, its endpoints are `nil` — an empty
    window, which is a real answer rather than an error.

  ### Examples

      iex> {:ok, morning} =
      ...>   LocalizePad.Temporal.Window.new(~T[09:00:00], ~T[12:00:00], date: ~D[2026-06-15])
      iex> {:ok, afternoon} =
      ...>   LocalizePad.Temporal.Window.new(~T[11:00:00], ~T[17:00:00], date: ~D[2026-06-15])
      iex> LocalizePad.Temporal.Window.hours(
      ...>   LocalizePad.Temporal.Window.intersect(morning, afternoon)
      ...> )
      1.0

  """
  @spec intersect(t(), t()) :: t()
  def intersect(%__MODULE__{} = left, %__MODULE__{} = right) do
    start = later(left.from, right.from)
    finish = earlier(left.to, right.to)

    if start && finish && DateTime.compare(start, finish) == :lt do
      %__MODULE__{from: start, to: finish}
    else
      %__MODULE__{from: nil, to: nil}
    end
  end

  defp later(nil, _right), do: nil
  defp later(_left, nil), do: nil
  defp later(left, right), do: if(DateTime.compare(left, right) == :gt, do: left, else: right)

  defp earlier(nil, _right), do: nil
  defp earlier(_left, nil), do: nil
  defp earlier(left, right), do: if(DateTime.compare(left, right) == :lt, do: left, else: right)

  @doc """
  Whether the window is empty.

  ### Arguments

  * `window` - the window to test.

  ### Returns

  * `true` or `false`.

  """
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{from: nil}), do: true
  def empty?(%__MODULE__{to: nil}), do: true
  def empty?(%__MODULE__{}), do: false

  @doc """
  The window's length in hours.

  ### Arguments

  * `window` - the window to measure.

  ### Returns

  * A float. An empty window is zero hours long.

  """
  @spec hours(t()) :: float()
  def hours(%__MODULE__{} = window) do
    if empty?(window), do: 0.0, else: DateTime.diff(window.to, window.from) / 3600
  end

  @doc """
  Formats a window as its length, in the given locale.

  ### Arguments

  * `window` - the window to format.

  * `options` - a keyword list of options.

  ### Options

  * `:locale` - the locale to format in. Defaults to `Localize.get_locale/0`.

  ### Returns

  * `{:ok, string}` on success, or `{:error, reason}`.

  """
  @spec format(t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def format(%__MODULE__{} = window, options \\ []) do
    locale = Keyword.get_lazy(options, :locale, &Localize.get_locale/0)

    if empty?(window) do
      # Deliberately a sentence rather than "0 hours". Two teams whose hours do
      # not meet are asking whether they *ever* meet, and zero is easy to read
      # as a rounding artefact.
      {:ok, no_overlap(locale)}
    else
      window.to
      |> DateTime.diff(window.from)
      |> Localize.Duration.new_from_seconds()
      |> Localize.Duration.to_string(locale: locale)
    end
  end

  # Not yet a translated message: the operator lexicon and the answer
  # vocabulary both arrive with M6, and inventing a half-localized string now
  # would be worse than one honest English one.
  defp no_overlap(_locale), do: "no overlap"
end
