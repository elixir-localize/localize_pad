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

    test "a word Unity does not alias stays prose" do
      # Unrecognised words are noise, and that rule is what makes
      # `19 + 22 for 2 people` an answer rather than an error.
      assert answer("120 * 3 people") == "360"
      assert answer("120 * 3 sticks") == "360"
    end

    test "a word Unity does alias becomes a quantity, common or not" do
      # Unity 1.1 derives plurals from the CLDR unit list, which carries a
      # `night` unit and a `cup`. So `3 nights` is now three nights rather than
      # prose, and the product of a rate and a night is a quantity that will
      # not add into a plain subtotal.
      #
      # This is recorded rather than worked around: the vocabulary is Unity's
      # to define, and a table here second-guessing it is what the last
      # workaround was.
      assert answer("120 * 3 nights") == "360 nights"
      assert answer("2 cups") == "2 cups"
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
      assert answer("7:30 bis 20:45", locale: :de) == "13 Stunden, 15 Minuten"
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

  describe "workdays follow the reader's working week" do
    # The clearest single case of the two halves of the product being the same
    # thing. Soulver hardcodes Monday to Friday; CLDR knows better, Tempo reads
    # it, and the territory comes from the sheet's own locale.
    test "Friday is a workday in the US and not in Saudi Arabia" do
      assert answer("is Friday, August 21, 2026 a workday", locale: :en) == "yes"
      assert answer("is Friday, August 21, 2026 a workday", locale: :"ar-SA") == "no"
    end

    test "Sunday is the mirror image" do
      assert answer("is Sunday, August 23, 2026 a workday", locale: :en) == "no"
      assert answer("is Sunday, August 23, 2026 a workday", locale: :"ar-SA") == "yes"
    end

    test "counting working days between two dates" do
      assert answer("workdays from April 12, 2026 to June 15, 2026") == "45"
    end

    test "shifting a date by working days skips the weekend" do
      # A Thursday plus two working days is the following Monday.
      assert answer("December 24, 2026 + 2 workdays") == "December 28, 2026"
    end

    test "naming the weekday, asked in the sheet's own language" do
      # The question is asked in each language, not only answered in it. The
      # English phrasing used to work under `:de` because the matcher's
      # vocabulary was hardcoded English; that was the same defect as a German
      # sheet accepting `per`, and it is gone.
      assert answer("day of the week on January 24, 1984", locale: :en) == "Tuesday"
      assert answer("welcher Wochentag ist der 24.01.1984", locale: :de) == "Dienstag"
      assert answer("quel jour de la semaine est le 24/01/1984", locale: :fr) == "mardi"
      assert answer("qué día de la semana es el 24/01/1984", locale: :es) == "martes"
    end

    test "workday questions are asked in the sheet's own language too" do
      # German distinguishes these and so does the lexicon: `Werktag` is a
      # working day, `Wochentag` a day of the week. Flattening them would
      # answer the wrong one of the two questions.
      assert answer("ist der 3. Juli 2026 ein Werktag", locale: :de) == "ja"
      assert answer("3 Werktage nach dem 24. Dezember 2026", locale: :de) == "29. Dezember 2026"
      assert answer("3 Werktage vor dem 24. Dezember 2026", locale: :de) == "21. Dezember 2026"

      assert answer("le 3 juillet 2026 est-il un jour ouvrable", locale: :fr) == "oui"
      assert answer("es el 3 de julio de 2026 un día laborable", locale: :es) == "sí"
    end

    test "an English workday phrase is not a German one" do
      # `workday` is not a German word, so a German sheet reads it as prose.
      refute answer("is 3 July 2026 a workday", locale: :de) == "ja"
    end

    test "public holidays are not counted yet" do
      # Soulver answers December 30 here, because it treats Christmas as a
      # holiday. Ours answers December 28: a workday is currently a non-weekend
      # day, and holidays arrive with the `.ics` work.
      refute answer("December 24, 2026 + 2 workdays") == "December 30, 2026"
    end
  end

  describe "the same date, named by another calendar" do
    doctest LocalizePad.Temporal.Calendars

    test "converting out of Gregorian" do
      assert answer("2026-06-15 in Hebrew") == "30 Sivan 5786"
      assert answer("2026-06-15 in Coptic") == "Paona 8, 1742 AM"
      assert answer("June 15, 2026 in Julian") == "June 2, 2026"
    end

    test "the answer is localized, not transliterated" do
      # CLDR has patterns per calendar, so a Japanese date on a Japanese sheet
      # gets its imperial era and Japanese numerals.
      # Written with the Japanese conversion arrow, because `in` is not a
      # Japanese word and a sheet in Japanese is read in Japanese.
      assert answer("2026-06-15 → Japanese", locale: :ja) == "令和8年6月15日"
      assert answer("2026-06-15 in Buddhist", locale: :th) =~ "2569"
    end

    test "a calendar name in prose is not a conversion" do
      # `Chinese`, `Indian` and `Japanese` are ordinary words. A note
      # mentioning one must not sprout a date in the margin — the same rule
      # that keeps `flight to Paris` from becoming a clock reading.
      assert shown("trip to Chinese restaurant") == nil
      assert shown("Hebrew") == nil
    end

    test "an out-of-range conversion is reported, not raised" do
      # Several calendars are astronomically computed and reject dates outside
      # the installed ephemeris by raising. The render path catches it.
      assert {:error, %Calendrical.UnsupportedDateRangeError{}} =
               LocalizePad.Temporal.Calendars.convert(~D[9999-01-01], Calendrical.Persian)
    end
  end

  describe "dates that are not precise" do
    doctest LocalizePad.Temporal.Uncertain

    # Historians and archivists write dates like this constantly, and every
    # calculator makes them convert to something precise first — which is
    # exactly the information they are trying not to assert.
    test "a decade is a masked year" do
      assert answer("the 1560s") == "A masked year spanning the 1560s."
      assert answer("the 1990s") == "A masked year spanning the 1990s."
    end

    test "an approximation keeps its qualification" do
      assert answer("circa 2022") == "The year 2022. Approximate."
      assert answer("circa 600 BCE") == "The year -600. Approximate."
    end

    test "a plain year is still a number" do
      assert answer("1984") == "1,984"
      assert answer("2026 + 1") == "2,027"
    end

    test "a trailing s that means seconds still means seconds" do
      # `s` is the CLDR abbreviation for `second`, so the decade matcher has to
      # accept it as either — without swallowing real unit expressions.
      assert answer("3 s to ms") == "3,000 milliseconds"
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
