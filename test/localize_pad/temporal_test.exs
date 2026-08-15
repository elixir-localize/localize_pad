defmodule LocalizePad.TemporalTest do
  use ExUnit.Case, async: true

  alias LocalizePad.Sheet
  alias LocalizePad.Temporal
  alias LocalizePad.Temporal.{Scanner, Window}

  doctest LocalizePad.Temporal
  doctest LocalizePad.Temporal.Scanner

  defp answer(source, options \\ []) do
    [line] = Sheet.new(source, Keyword.put_new(options, :locale, :en)).lines
    line.formatted || line.error
  end

  # What the answer column actually displays: an error shows nothing at all.
  defp shown(source, options \\ []) do
    [line] = Sheet.new(source, Keyword.put_new(options, :locale, :en)).lines
    line.formatted
  end

  describe "the shape filter" do
    # This is the safety mechanism for the whole temporal layer. Calendrical
    # will happily parse "2026" as a year and "11" as an hour, so without a
    # filter every number in every sheet would become a date. Each of these is
    # a case where refusing is the right answer.
    test "a bare year is a number, not a date" do
      assert answer("2026 + 1") == "2,027"
    end

    test "a decimal is a number, not a date" do
      assert answer("9.8 * 2") == "19.6"
      assert answer("1234567 + 0.5") == "1,234,567.5"
    end

    test "a division is a division, not a date" do
      assert answer("100 / 5") == "20"
    end

    test "a compound unit is not a date" do
      assert answer("100 kg * 9.8 m/s^2") == "980 kilogram-meter-per-square-second"
    end

    test "an ordinary sum is untouched" do
      assert Scanner.scan("19 + 22", locale: :en) == [{:text, "19 + 22"}]
    end
  end

  describe "recognising dates" do
    test "a month name with a day" do
      assert [{:temporal, fields, "10 June"}] = Scanner.scan("10 June", locale: :en)
      assert fields.month == 6
      assert fields.day == 10
    end

    test "a fully separated numeric date" do
      assert [{:temporal, _fields, "12/02/1988"}] = Scanner.scan("12/02/1988", locale: :en)
    end

    test "longest match wins, so a weekday prefix joins its date" do
      assert [{:temporal, _fields, "Saturday, May 16, 2026"}] =
               Scanner.scan("Saturday, May 16, 2026", locale: :en)
    end

    test "the rest of the line survives around a claimed date" do
      assert [{:temporal, _fields, "June 12"}, {:text, " + 3 weeks"}] =
               Scanner.scan("June 12 + 3 weeks", locale: :en)
    end

    test "clock times" do
      assert [{:temporal, %{hour: 7, minute: 45}, "7:45am"}, {:text, _rest} | _] =
               Scanner.scan("7:45am - 4:20pm", locale: :en)
    end

    test "dates are read in the sheet's locale, not English" do
      assert [{:temporal, fields, "16.05.2026"}] = Scanner.scan("16.05.2026", locale: :de)
      assert {fields.day, fields.month} == {16, 5}

      assert [{:temporal, fields, "10 juin 2026"}] = Scanner.scan("10 juin 2026", locale: :fr)
      assert {fields.day, fields.month} == {10, 6}
    end
  end

  describe "the missing year" do
    # Soulver's rule, and ours: a date with no year means whichever adjacent
    # year puts it nearest to today. These use a fixed reference so the suite
    # does not change answers depending on the day it runs.
    test "a month just ahead means next year when it is closer" do
      {:ok, tempo} =
        Temporal.resolve(%{month: 1, day: 12}, reference_date: ~D[2019-12-05])

      assert Tempo.to_date(tempo) == {:ok, ~D[2020-01-12]}
    end

    test "a month just behind means this year when it is closer" do
      {:ok, tempo} =
        Temporal.resolve(%{month: 11, day: 1}, reference_date: ~D[2019-12-05])

      assert Tempo.to_date(tempo) == {:ok, ~D[2019-11-01]}
    end

    test "a stated year is left alone" do
      {:ok, tempo} =
        Temporal.resolve(%{year: 1988, month: 2, day: 12}, reference_date: ~D[2026-08-15])

      assert Tempo.to_date(tempo) == {:ok, ~D[1988-02-12]}
    end
  end

  describe "date arithmetic" do
    test "adding a duration to a date" do
      assert answer("June 12, 2026 + 3 weeks") == "July 3, 2026"
    end

    test "subtracting a duration from a date" do
      assert answer("April 1, 2019 - 3 months") == "January 1, 2019"
    end

    test "the span between two dates is a duration, not an instant" do
      assert answer("January 10, 2027 - February 5, 2027") == "26 days"
    end

    test "durations come from the unit engine, so any calendar unit works" do
      assert answer("June 12, 2026 + 2 days") == "June 14, 2026"
      assert answer("June 12, 2026 + 1 year") == "June 12, 2027"
      assert answer("June 12, 2026 + 2 months") == "August 12, 2026"
    end

    test "a plural word that is not a calendar unit stays prose" do
      # CLDR has a `night` unit, so a blanket plural fallback would turn this
      # into "360 nights" — and a quantity will not add into a subtotal the way
      # a number does. Unrecognised words are noise; that rule is worth more
      # than catching one extra unit.
      assert answer("120 * 3 nights") == "360"
    end

    test "a non-calendar quantity cannot shift a date" do
      assert {:not_a_calendar_unit, "meter"} = answer("June 12, 2026 + 3 meters")
    end
  end

  describe "relative phrasing" do
    # "3 weeks after March 14" states the duration first and the date second,
    # the reverse of "March 14 + 3 weeks". Both reach the same code path.
    test "after" do
      assert answer("3 weeks after March 14, 2019") == "April 4, 2019"
    end

    test "before" do
      assert answer("28 days before March 12, 2026") == "February 12, 2026"
    end
  end

  describe "localized rendering" do
    test "a date is written in the sheet's locale" do
      assert answer("June 15, 2026", locale: :en) == "June 15, 2026"
      assert answer("15.06.2026", locale: :de) == "15. Juni 2026"
      assert answer("15 juin 2026", locale: :fr) == "15 juin 2026"
    end

    test "a duration is written in the sheet's locale" do
      assert answer("January 10, 2027 - February 5, 2027", locale: :en) == "26 days"
      assert answer("10.01.2027 - 05.02.2027", locale: :de) == "26 Tage"
    end
  end

  describe "deictic dates" do
    test "today, tomorrow and yesterday resolve against the present" do
      today = Date.utc_today()

      assert answer("today") == expected_date(today)
      assert answer("tomorrow") == expected_date(Date.add(today, 1))
      assert answer("yesterday") == expected_date(Date.add(today, -1))
    end

    test "a deictic date takes part in arithmetic like any other" do
      expected = Date.utc_today() |> Date.add(21) |> expected_date()

      assert answer("today + 3 weeks") == expected
    end

    defp expected_date(date) do
      {:ok, formatted} = Localize.Date.to_string(date, locale: :en, format: :long)
      formatted
    end
  end

  describe "clock-time spans" do
    # Soulver's own documentation concedes the minus sign is ambiguous with
    # clock times — most people read `5pm - 7pm` as a range and `5pm - 2pm` as
    # a subtraction. Measuring the gap makes both readings agree, so that is
    # what both `to` and `-` do here.
    test "a span written with 'to'" do
      assert answer("7:30 to 20:45") == "13 hours, 15 minutes"
      assert answer("9:45 am to 6:35 pm") == "8 hours, 50 minutes"
    end

    test "a span written with a minus sign" do
      assert answer("5pm - 7pm") == "2 hours"
    end

    test "a second time earlier on the clock means the following day" do
      # Rather than eleven hours in the negative direction.
      assert answer("4pm to 3am") == "11 hours"
    end

    test "spans are rendered in the sheet's locale" do
      assert answer("7:30 to 20:45", locale: :de) == "13 Stunden, 15 Minuten"
    end
  end

  describe "time zones" do
    # These assert the *offset arithmetic* rather than a literal clock face,
    # because the answer depends on which side of a daylight-saving boundary
    # the suite runs on. Comparing against a freshly computed conversion keeps
    # the test honest all year round.
    defp converted(time, from_zone, to_zone) do
      {:ok, datetime} = DateTime.new(Date.utc_today(), time, from_zone)
      {:ok, shifted} = DateTime.shift_zone(datetime, to_zone)

      {:ok, formatted} =
        Localize.Time.to_string(DateTime.to_time(shifted), locale: :en, format: :short)

      formatted
    end

    test "a city to a city" do
      assert answer("6pm Sydney in Chicago") ==
               converted(~T[18:00:00], "Australia/Sydney", "America/Chicago")
    end

    test "a multi-word city name" do
      assert answer("9am New York in London") ==
               converted(~T[09:00:00], "America/New_York", "Europe/London")
    end

    test "an airport code, and a country standing for its capital" do
      assert answer("7:30am LAX in Japan") ==
               converted(~T[07:30:00], "America/Los_Angeles", "Asia/Tokyo")
    end

    test "a zone abbreviation, resolved by Calendrical rather than our table" do
      assert answer("2am PST to GMT") ==
               converted(~T[02:00:00], "America/Los_Angeles", "Etc/GMT")
    end

    test "a city name in ordinary prose is not a clock reading" do
      # The whole reason zones are never standalone values. Were they, every
      # note mentioning a city would sprout a time in the margin. What matters
      # is that no answer is *shown* — whether the line records a `:bare_zone`
      # error along the way is an internal detail.
      assert shown("flight to Paris") == nil
      assert shown("meeting in London next week") == nil
      assert shown("Paris") == nil
    end

    test "a time with no source zone cannot be converted" do
      # `6pm in Chicago` leaves out where 6pm *is*. Guessing the reader's own
      # zone would give a different answer for every reader.
      assert answer("6pm in Chicago") == :zone_without_source
    end
  end

  describe "overlapping windows" do
    doctest LocalizePad.Temporal.Window

    # The question a distributed team actually has, and the one no notepad
    # calculator has answered. Asserted against freshly computed conversions so
    # the suite is right on both sides of a daylight-saving boundary.
    defp overlap_hours(from_zone, to_zone) do
      {:ok, left} = Window.new(~T[09:00:00], ~T[17:00:00], zone: from_zone)
      {:ok, right} = Window.new(~T[09:00:00], ~T[17:00:00], zone: to_zone)

      left |> Window.intersect(right) |> Window.hours()
    end

    test "two cities that share part of a working day" do
      expected = overlap_hours("Europe/London", "America/New_York")

      assert expected > 0

      assert answer("9am to 5pm London and 9am to 5pm New York") ==
               expected |> trunc() |> then(&"#{&1} hours")
    end

    test "two cities that share none of it" do
      assert overlap_hours("Europe/London", "Asia/Tokyo") == 0.0
      assert answer("9am to 5pm London and 9am to 5pm Tokyo") == "no overlap"
      assert answer("9am to 5pm New York and 9am to 5pm Tokyo") == "no overlap"
    end

    test "an empty overlap says so rather than reading as zero" do
      # "0 hours" is too easily read as a rounding artefact. The question is
      # whether they ever meet, and the answer is no.
      assert answer("9am to 5pm London and 9am to 5pm Tokyo") == "no overlap"
    end

    test "a clock span still renders as its length" do
      # A span is now an interval internally, so that endpoints survive for
      # set operations. Nothing about the familiar answer changes.
      assert answer("7:30 to 20:45") == "13 hours, 15 minutes"
      assert answer("4pm to 3am") == "11 hours"
      assert answer("5pm - 7pm") == "2 hours"
    end

    test "a zone re-reads the wall clock rather than shifting the instants" do
      # 9am London moved to New York is New York's 9am, not 4am.
      {:ok, window} = Window.new(~T[09:00:00], ~T[17:00:00], zone: "Europe/London")
      {:ok, moved} = Window.in_zone(window, "America/New_York")

      assert moved.from |> DateTime.to_time() == ~T[09:00:00]
      assert moved.from.time_zone == "America/New_York"
    end
  end

  describe "the running total" do
    # Adding up the dates in a sheet is meaningless. Before this was guarded,
    # the first date seeded the accumulator and the total read as a date while
    # every number below it was skipped.
    test "dates do not contribute to the total" do
      sheet = Sheet.new("June 12, 2026 + 3 weeks\n19\n22", locale: :en)

      assert Sheet.total(sheet) == 41
    end

    test "a sheet of only dates has no total" do
      sheet = Sheet.new("June 12, 2026 + 3 weeks", locale: :en)

      assert Sheet.total(sheet) == nil
    end
  end

  describe "declining rather than guessing" do
    test "a quarter is a span, and spans are not supported yet" do
      assert {:error, {:unsupported_temporal, :quarter}} =
               Temporal.resolve(%{year: 2026, quarter: 2})
    end

    test "a fractional duration has no unambiguous calendar meaning" do
      {:ok, half_week} = Localize.Unit.new(3.5, "week")

      assert {:error, {:fractional_duration, 3.5}} = Temporal.duration(half_week)
    end

    test "an empty field map resolves to nothing" do
      assert Temporal.resolve(%{}) == {:error, :no_temporal_fields}
    end
  end
end
