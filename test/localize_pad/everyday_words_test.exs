defmodule LocalizePad.EverydayWordsTest do
  use ExUnit.Case, async: true

  alias LocalizePad.Sheet

  doctest LocalizePad.Units, only: [everyday?: 1]

  defp answer(source, locale \\ :en) do
    source
    |> Sheet.new(locale: locale)
    |> Map.fetch!(:lines)
    |> List.last()
    |> then(&(&1.formatted || &1.error))
  end

  describe "words that are units and also ordinary English" do
    # `cup`, `stone`, `point`, `bar`, `knot` and `bit` are all real units, and
    # Unity is right to have them. They are also words people write in a
    # notepad, and there the unit reading produces nonsense.
    test "prose keeps its number and loses the unit" do
      assert answer("hotel = 120\nhotel * 3 nights") == "360"
      assert answer("beer = 8\nbeer * 4 bars") == "32"
      assert answer("tip = 5\ntip * 2 drops") == "10"
    end

    test "a line that used to be refused now answers" do
      # `500 + 300 points` was `{:incompatible, :number, "point"}` — a working
      # sum refused because the last word claimed to be a unit.
      assert answer("500 + 300 points") == "800"
    end

    test "and one that used to answer nonsense" do
      assert answer("3 parts water") == "3"
    end
  end

  describe "but they are still units where the line converts" do
    test "as the source of a conversion" do
      assert answer("2 cups to mL") == "473.176473 milliliters"
      assert answer("11 stone to kg") == "69.853225 kilograms"
      assert answer("20 knots to km/h") == "37.04 kilometers per hour"
    end

    test "as the target of one" do
      # The rule cannot be "a unit appears after `to`" — here the everyday word
      # *is* the target, and the unambiguous unit is on the left.
      assert answer("500 mL to cups") == "2.113376 cups"
    end

    test "and when the target is the reader's own units" do
      # `local units` is itself a resolved target, so this line has no other
      # unit in it to prove it converts — which is why the rule treats a
      # preference as a conversion in its own right.
      assert answer("2 cups in local units", "en-US") == "28.875 cubic inches"
    end
  end

  describe "what decides the reading" do
    test "a conversion keyword alone is not enough" do
      # `in` is a conversion keyword, but `the basket` is not a unit, so nothing
      # in this line asks for `items` to be one.
      refute answer("12 items in the basket") =~ "item"
    end

    test "an unambiguous unit alone is not enough either" do
      # There is a real unit here and no conversion, so `nights` stays prose —
      # which leaves `3 km + 2`, and a length plus a bare number is refused.
      # The refusal naming `:number` rather than `"night"` is the evidence.
      assert answer("3 km + 2 nights") == {:incompatible, "kilometer", :number}
    end

    test "the decision is per line, not per sheet" do
      # Each line is read on its own terms, so one converting line does not
      # turn the word into a unit everywhere below it.
      source = "2 cups to mL\nhotel = 120\nhotel * 3 nights"

      assert answer(source) == "360"
    end
  end

  describe "the ordinary unit vocabulary is untouched" do
    test "unambiguous units are never demoted" do
      assert answer("3 meters to feet") == "9.84252 feet"
      assert answer("hotel = 120\nhotel * 3 weeks") == "360 weeks"
    end

    test "and `in` still reads as inch where it always did" do
      assert answer("3 in") == "3 inches"
    end
  end

  describe "this is an English problem" do
    test "other locales are unaffected" do
      # `Nächte` is nothing like the identifier `night`, and the CLDR
      # display-name index is not consulted for English at all — so the list
      # only ever applies to one language.
      assert LocalizePad.Units.everyday?("Nächte") == false
    end
  end
end
