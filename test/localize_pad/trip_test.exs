defmodule LocalizePad.TripTest do
  use ExUnit.Case, async: true

  alias LocalizePad.{Line, Sheet, Trip}

  doctest LocalizePad.Trip

  defp answers(source, options \\ []) do
    source
    |> String.trim_trailing()
    |> Sheet.new(Keyword.put_new(options, :locale, :en))
    |> Map.fetch!(:lines)
    |> Enum.map(& &1.formatted)
  end

  defp errors(source, options \\ []) do
    source
    |> String.trim_trailing()
    |> Sheet.new(Keyword.put_new(options, :locale, :en))
    |> Map.fetch!(:lines)
    |> Enum.map(& &1.error)
  end

  @japan """
  trip from March 3, 2026
  3 nights in Tokyo
  5 nights in Kyoto
  4 nights in Osaka
  5 nights in Sapporo
  trip ends March 22, 2026
  """

  describe "an itinerary" do
    test "every stop answers with the dates it occupies" do
      assert answers(@japan) == [
               "17 nights, 2 to spare",
               "Mar 3\u2009–\u20096, 2026",
               "Mar 6\u2009–\u200911, 2026",
               "Mar 11\u2009–\u200915, 2026",
               "Mar 15\u2009–\u200920, 2026",
               "Mar 22, 2026"
             ]
    end

    test "each stop begins where the last one ended" do
      # Three nights from the 3rd is the 6th, and the next stop starts there
      # rather than a day later. A trip has no gap in it unless one is written.
      assert answers("trip from March 3, 2026\n3 nights in Tokyo\n1 night in Kyoto") ==
               ["4 nights", "Mar 3\u2009–\u20096, 2026", "Mar 6\u2009–\u20097, 2026"]
    end

    test "changing one stop moves every stop below it" do
      shorter = String.replace(@japan, "3 nights in Tokyo", "1 night in Tokyo")

      assert answers(shorter) == [
               "15 nights, 4 to spare",
               "Mar 3\u2009–\u20094, 2026",
               "Mar 4\u2009–\u20099, 2026",
               "Mar 9\u2009–\u200913, 2026",
               "Mar 13\u2009–\u200918, 2026",
               "Mar 22, 2026"
             ]
    end

    test "a stop spanning a month is written as one" do
      # CLDR decides how a range that crosses a month is abbreviated, which is
      # why neither form is written down in this project.
      assert answers("trip from March 30, 2026\n4 nights in Rome") ==
               ["4 nights", "Mar 30\u2009–\u2009Apr 3, 2026"]
    end

    test "and one spanning a year says both years" do
      assert answers("trip from December 30, 2026\n4 nights in Vienna") ==
               ["4 nights", "Dec 30, 2026\u2009–\u2009Jan 3, 2027"]
    end
  end

  describe "the time budget" do
    test "an end date on the opening line says how much is left" do
      assert List.first(answers("trip: March 3 to March 22, 2026\nTokyo: 3 nights")) ==
               "3 nights, 16 to spare"
    end

    test "and a closing line does the same" do
      assert List.first(
               answers("trip from March 3, 2026\n3 nights in Tokyo\ntrip ends March 22, 2026")
             ) ==
               "3 nights, 16 to spare"
    end

    test "going over says so, which is the point of writing the end date" do
      over = String.replace(@japan, "5 nights in Sapporo", "9 nights in Sapporo")

      assert List.first(answers(over)) == "21 nights, 2 over"
    end

    test "landing exactly on it says that too" do
      assert List.first(answers("trip from March 3, 2026 to March 6, 2026\n3 nights in Tokyo")) ==
               "3 nights, exactly"
    end

    test "with no end date, the trip is only its own length" do
      assert List.first(answers("trip from March 3, 2026\n3 nights in Tokyo")) == "3 nights"
    end

    test "one night is a night, not `1 nights`" do
      assert List.first(answers("trip from March 3, 2026\n1 night in Tokyo")) == "1 night"
    end
  end

  describe "the two spellings" do
    test "the label form plans the same trip as the prose form" do
      prose = "trip from March 3, 2026\n3 nights in Tokyo\n5 nights in Kyoto"
      label = "trip from March 3, 2026\nTokyo: 3 nights\nKyoto: 5 nights"

      assert answers(prose) == answers(label)
    end

    test "and a sheet may mix them" do
      mixed = "trip from March 3, 2026\nTokyo: 3 nights\n5 nights in Kyoto"

      assert answers(mixed) == [
               "8 nights",
               "Mar 3\u2009–\u20096, 2026",
               "Mar 6\u2009–\u200911, 2026"
             ]
    end

    test "`days` is accepted where `nights` is, and means the same span" do
      assert answers("trip from March 3, 2026\n3 days in Tokyo") ==
               answers("trip from March 3, 2026\n3 nights in Tokyo")
    end

    test "but a labelled line outside a trip is still an ordinary line" do
      # `Tokyo: 3 nights` is only a stop in the company of a trip. Claiming it
      # everywhere would change what an ordinary sheet means.
      assert answers("Tokyo: 3 nights") == ["3"]
    end
  end

  describe "the bounds of a trip" do
    test "a heading ends it" do
      source = """
      trip from March 3, 2026
      3 nights in Tokyo
      # Afterwards
      2 nights in Kyoto
      """

      assert answers(source) == ["3 nights", "Mar 3\u2009–\u20096, 2026", nil, nil]
      assert Enum.at(errors(source), 3) == :no_trip
    end

    test "and so does the next trip" do
      source = """
      trip from March 3, 2026
      3 nights in Tokyo
      trip from June 1, 2026
      2 nights in Kyoto
      """

      assert answers(source) == [
               "3 nights",
               "Mar 3\u2009–\u20096, 2026",
               "2 nights",
               "Jun 1\u2009–\u20093, 2026"
             ]
    end

    test "a stop with no trip above it says so rather than going blank" do
      assert errors("3 nights in Tokyo") == [:no_trip]
      assert LocalizePad.Refusal.message(:no_trip, locale: :en) =~ "trip from"
    end

    test "and a trip with no start date says what it is missing" do
      assert errors("trip from nowhere\n3 nights in Tokyo") == [:no_start_date, :no_trip]
    end
  end

  describe "a trip among other lines" do
    test "does not disturb the sheet's total" do
      source = """
      hotel: $240
      flight: $89
      trip from March 3, 2026
      3 nights in Tokyo
      """

      assert Money.equal?(
               Sheet.total(Sheet.new(String.trim(source), locale: :en), %{}),
               Money.new(:USD, "329.00")
             )
    end

    test "and ordinary lines inside one are untouched" do
      source = """
      trip from March 3, 2026
      3 nights in Tokyo
      19 + 22
      2 nights in Kyoto
      """

      assert answers(source) == [
               "5 nights",
               "Mar 3\u2009–\u20096, 2026",
               "41",
               "Mar 6\u2009–\u20098, 2026"
             ]
    end
  end

  describe "the dates are the reader's" do
    test "a German sheet reads German dates and answers in German" do
      # Both halves are the reader's: the dates come from CLDR's interval
      # format and the nights from the message catalogue.
      assert answers("trip: 3.3.2026\n3 nights in Tokio", locale: :de) ==
               ["3 Nächte", "03.03.2026\u2009–\u200906.03.2026"]
    end

    test "and one night is one night in every language" do
      assert answers("trip: 3.3.2026\n1 night in Tokio", locale: :de) |> List.first() ==
               "1 Nacht"

      assert answers("trip: 3.3.2026\n1 night in Tokyo", locale: :fr) |> List.first() ==
               "1 nuit"

      assert answers("trip: 3.3.2026\n1 night in Tokyo", locale: :es) |> List.first() ==
               "1 noche"
    end

    test "and an Australian sheet reads day-first" do
      # `3/6/2026` is 3 June here and 6 March in `en-US`, and the trip starts
      # on whichever the reader meant.
      assert answers("trip from 3/6/2026\n2 nights in Sydney", locale: "en-AU") ==
               ["2 nights", "3\u20135 June 2026"]
    end
  end

  describe "reading a line as a stop" do
    test "the prose form gives its count and its place" do
      assert Trip.stop(Line.classify(0, "3 nights in Tokyo")) == {:ok, 3, "Tokyo"}
    end

    test "the label form does too" do
      assert Trip.stop(Line.classify(0, "Kyoto: 5 nights")) == {:ok, 5, "Kyoto"}
    end

    test "and an ordinary line is not a stop" do
      assert Trip.stop(Line.classify(0, "19 + 22")) == :error
      assert Trip.stop(Line.classify(0, "Tokyo: $300")) == :error
    end
  end
end
