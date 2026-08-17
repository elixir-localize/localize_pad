defmodule LocalizePad.AlmanacTest do
  use ExUnit.Case, async: true

  alias LocalizePad.{Almanac, Sheet}

  doctest LocalizePad.Almanac
  doctest LocalizePad.Almanac.Point

  # A fixed date, so an answer can be checked against a published one rather
  # than against whatever this module computed the day the test was written.
  @date ~D[2026-06-21]

  defp answers(source, options) do
    source
    |> Sheet.new(Keyword.put_new(options, :locale, :en))
    |> Map.fetch!(:lines)
    |> Enum.map(& &1.formatted)
  end

  defp answer(line, options \\ []) do
    [formatted] = answers(line, options)

    formatted
  end

  defp error(line, options \\ []) do
    [%{error: error}] = Sheet.new(line, Keyword.put_new(options, :locale, :en)).lines

    error
  end

  describe "the coordinates" do
    test "come from IANA's own table, to the arc-minute or better" do
      # Chicago's principal city is at 41°51'N 87°39'W in `zone.tab`.
      {:ok, {longitude, latitude}} = Almanac.coordinates("America/Chicago")

      assert_in_delta latitude, 41.85, 0.001
      assert_in_delta longitude, -87.65, 0.001
    end

    test "read the seconds where the table gives them" do
      # Tokyo is written `+353916+1394441` — degrees, minutes *and* seconds.
      {:ok, {longitude, latitude}} = Almanac.coordinates("Asia/Tokyo")

      assert_in_delta latitude, 35.6544, 0.001
      assert_in_delta longitude, 139.7447, 0.001
    end

    test "carry the sign of both hemispheres" do
      {:ok, {longitude, latitude}} = Almanac.coordinates("Pacific/Auckland")

      assert latitude < 0
      assert longitude > 0
    end

    test "cover every zone the sheet can name" do
      # The place vocabulary and the coordinate table are separate data, and a
      # name the sheet accepts but cannot place would refuse with a message
      # about a place the reader typed correctly.
      unplaceable =
        LocalizePad.Temporal.Zones.zones()
        |> Enum.reject(&match?({:ok, _point}, Almanac.coordinates(&1)))

      assert unplaceable == []
    end
  end

  describe "sun and moon" do
    test "sunrise is answered on the clock of the place asked about" do
      # Reykjavik at midsummer: the sun is up before three in the morning.
      assert answer("sunrise in Reykjavik on June 21, 2026") == "2:54\u202FAM"
    end

    test "and the place is what changes it, not the reader" do
      # Midwinter in Sydney and the equator in between: the same solstice is a
      # nine-hour day in one place and a twelve-hour day in the other.
      assert answer("sunrise in Sydney on June 21, 2026") == "6:59\u202FAM"
      assert answer("sunset in Sydney on June 21, 2026") == "4:53\u202FPM"
      assert answer("sunrise in Singapore on June 21, 2026") == "7:00\u202FAM"
      assert answer("sunset in Singapore on June 21, 2026") == "7:12\u202FPM"
    end

    test "sunset in a northern midsummer is late, as it should be" do
      # Just after midnight, on the same day it rose at ten to three.
      assert answer("sunset in Reykjavik on June 21, 2026") == "12:03\u202FAM"
    end

    test "the moon rises and sets too" do
      assert answer("moonrise in Sydney on June 21, 2026") == "11:24\u202FAM"
      assert answer("moonset in Sydney on June 21, 2026") == "11:38\u202FPM"
    end

    test "a place named without a date is asked about today" do
      # Which day that is depends on where, so this only checks that a time
      # comes back at all — the fixed dates above are what pin the arithmetic.
      assert answer("sunrise in Tokyo") =~ ~r/\d/
    end
  end

  describe "the phase of the moon" do
    test "is named, drawn and measured" do
      # A full moon on the winter solstice of 2026, near enough.
      assert answer("moon phase on December 24, 2026") =~ "Full moon"
      assert answer("moon phase on December 24, 2026") =~ "🌕"
      assert answer("moon phase on December 24, 2026") =~ "100%"
    end

    test "and the name agrees with the emoji, sector for sector" do
      assert answer("moon phase on December 31, 2026") =~ "Last quarter"
      assert answer("moon phase on December 31, 2026") =~ "🌗"
    end

    test "needs no place, because a phase has none" do
      # Every other event here refuses without a location. This one is the same
      # moon from everywhere it is up.
      assert answer("moon phase today") =~ ~r/moon|crescent|quarter|gibbous/i
    end

    test "and its number is written the reader's way" do
      # The phase names are English; the percentage is CLDR's, in every locale,
      # and German puts a non-breaking space before the sign where English has
      # none. The date is German too, because the sheet is.
      assert answer("moon phase on 24.12.2026", locale: :de) =~ "100\u00A0%"
      assert answer("moon phase on December 24, 2026", locale: :en) =~ "100%"
    end
  end

  describe "when the line does not say where" do
    test "the reader's own zone answers it" do
      assert answer("sunrise on June 21, 2026", zone: "Atlantic/Reykjavik") == "2:54\u202FAM"
    end

    test "and a named place still beats it" do
      assert answer("sunrise in Sydney on June 21, 2026", zone: "Atlantic/Reykjavik") ==
               "6:59\u202FAM"
    end

    test "with no zone at all, the line asks for a place rather than guessing" do
      assert error("sunrise") == {:no_location, :sunrise}
      assert answer("sunrise") == nil
    end

    test "and says so in words the reader can act on" do
      message = LocalizePad.Refusal.message({:no_location, :sunrise}, locale: :en)

      assert message =~ "sunrise in Sydney"
    end
  end

  describe "events that do not happen" do
    test "Reykjavik in December still gets one, late in the morning" do
      # Just south of the Arctic circle, so the sun does rise — at twenty past
      # eleven, which is the answer that makes the next test worth having.
      assert answer("sunrise in Reykjavik on December 21, 2026") == "11:21\u202FAM"
    end

    test "and Longyearbyen in December has none at all" do
      assert error("sunrise on December 21, 2026", zone: "Arctic/Longyearbyen") ==
               {:no_event, :sunrise}

      assert answer("sunrise on December 21, 2026", zone: "Arctic/Longyearbyen") == nil
    end
  end

  describe "what the almanac does not claim" do
    test "an ordinary sum is still a sum" do
      assert answer("19 + 22") == "41"
    end

    test "a line that names an event and a recurrence keeps its recurrence" do
      # `Almanac.match/2` runs last for exactly this: claiming the line would
      # drop the `every` on the floor and answer for one day.
      assert answer("sunrise every Monday in June 2026") =~ "dates"
    end

    test "and a date on its own is a date" do
      assert answer("June 21, 2026") == "June 21, 2026"
    end
  end

  describe "the almanac in a sheet" do
    test "several lines answer independently" do
      source = """
      # Midsummer, north and south
      sunrise in Reykjavik on June 21, 2026
      sunrise in Sydney on June 21, 2026
      moon phase on June 21, 2026
      """

      assert [nil, north, south, phase, nil] = answers(source, [])
      assert north == "2:54\u202FAM"
      assert south == "6:59\u202FAM"
      assert phase =~ "First quarter"
    end

    test "the reference date is the date in the place asked about" do
      # `today` in Auckland is a day ahead of `today` in Los Angeles for much
      # of each day, and each line is read on its own clock.
      assert answer("sunrise in Auckland") =~ ~r/\d/
      assert answer("sunrise in Los Angeles") =~ ~r/\d/
    end

    test "a place beyond the sheet's own vocabulary is still a place" do
      # `Adelaide` is not one of the cities the rest of the sheet will name in
      # `6pm Adelaide`, and after `sunrise in` there is nothing else it could
      # be. The whole IANA table is in scope here for that reason.
      assert answer("sunrise in Adelaide on June 21, 2026") == "7:23\u202FAM"
      assert answer("moonrise in Port Moresby on June 21, 2026") == "11:35\u202FAM"
    end

    test "and a place that cannot be found refuses rather than moving the reader" do
      # The bug this pins: with a reader's zone set, an unfindable place fell
      # through to it and answered confidently for Sydney a line that plainly
      # said somewhere else.
      assert error("sunrise in Atlantis", zone: "Australia/Sydney") ==
               {:unknown_place, "Atlantis"}

      assert answer("sunrise in Atlantis", zone: "Australia/Sydney") == nil
    end

    test "which it says in the reader's own words, and their own capitals" do
      message = LocalizePad.Refusal.message({:unknown_place, "Atlantis"}, locale: :en)

      assert message =~ "Atlantis"
    end

    test "a phase is answered wherever it is asked from, findable place or not" do
      # The moon is the same moon. Refusing this for want of a location would
      # be refusing a question that never had one.
      assert answer("moon phase in Atlantis on 24 December 2026", locale: "en-GB") =~ "Full moon"
    end

    test "the date is still read the reader's way" do
      # `6.21.2026` is nothing in `en-AU` and June 21 in `en-US`; the almanac
      # inherits that from the tokenizer rather than parsing dates itself.
      assert answer("sunrise in Sydney on 21/6/2026", locale: "en-AU") == "6:59\u202Fam"
    end
  end

  describe "the words are counted as authored" do
    test "so the demo underline covers them" do
      authored = LocalizePad.Lexicon.authored(:en)

      assert MapSet.member?(authored, "sunrise")
      assert MapSet.member?(authored, "moonset")
      assert MapSet.member?(authored, "phase")
    end
  end

  test "the reference date option decides what today means" do
    assert Almanac.evaluate(:sunrise, %{date: nil, zone: "Australia/Sydney", locale: :en},
             reference_date: @date
           )
           |> elem(0) == :ok
  end
end
