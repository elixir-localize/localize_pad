defmodule LocalizePad.Temporal.Calendars do
  @moduledoc """
  Reading a date in another calendar — `2026-06-15 in Hebrew`.

  ## What this is for

  A date is a position in time; a *calendar* is one way of naming it. Most
  software offers exactly one naming, and users of the other eighteen convert
  by hand. Calendrical implements them all, so the only work here is
  recognising the calendar's name and handing the date over.

  The answers are properly localized, not transliterated: `2026-06-15 in
  Japanese` on a `:ja` sheet reads `令和8年6月15日` — the imperial era, the
  year within it, and the Japanese numerals — because `Localize.Date` formats
  through CLDR's patterns for that calendar.

  ## A calendar is never a value on its own

  Like a time zone, and for the same reason: `Chinese`, `Indian` and `Japanese`
  are ordinary English words, and a note mentioning one must not sprout a date
  in the margin. A calendar only means something as the target of a conversion.

  ## One direction, for now

  Converting *out* of Gregorian works for every calendar. Reading a date
  *written* in another calendar works for some — `29 Kislev 5786` parses —
  but not the Islamic ones, whose CLDR patterns Calendrical does not currently
  match against those month names. That is an upstream question rather than
  something to work around here.

  """

  @calendars %{
    "gregorian" => Calendar.ISO,
    "buddhist" => Calendrical.Buddhist,
    "chinese" => Calendrical.Chinese,
    "coptic" => Calendrical.Coptic,
    "ethiopic" => Calendrical.Ethiopic,
    "hebrew" => Calendrical.Hebrew,
    "indian" => Calendrical.Indian,
    "japanese" => Calendrical.Japanese,
    "julian" => Calendrical.Julian,
    "persian" => Calendrical.Persian,
    "jalali" => Calendrical.Persian,
    "roc" => Calendrical.ROC,
    "minguo" => Calendrical.ROC
  }

  @doc """
  Resolves a calendar's name to its module.

  ### Arguments

  * `name` - the calendar's name, in any case.

  ### Returns

  * `{:ok, module}` when the name is a calendar.

  * `:error` otherwise, which is the common case.

  ### Examples

      iex> LocalizePad.Temporal.Calendars.resolve("Hebrew")
      {:ok, Calendrical.Hebrew}

      iex> LocalizePad.Temporal.Calendars.resolve("breakfast")
      :error

  """
  @spec resolve(String.t()) :: {:ok, module()} | :error
  def resolve(name) when is_binary(name) do
    Map.fetch(@calendars, String.downcase(String.trim(name)))
  end

  @doc """
  Converts a date into another calendar.

  ### Arguments

  * `date` - a `t:Date.t/0`.

  * `calendar` - the target calendar module.

  ### Returns

  * `{:ok, date}` in the target calendar, or `{:error, reason}`.

  ### Examples

      iex> {:ok, date} =
      ...>   LocalizePad.Temporal.Calendars.convert(~D[2026-06-15], Calendrical.Hebrew)
      iex> date.year
      5786

  """
  @spec convert(Date.t(), module()) :: {:ok, Date.t()} | {:error, term()}
  def convert(%Date{} = date, calendar) do
    Date.convert(date, calendar)
  rescue
    # Several calendars are astronomically computed and reject dates outside
    # the range of the installed ephemeris — by raising rather than returning.
    # This is the render path of a live document, so catch it.
    exception -> {:error, exception}
  end
end
