defmodule LocalizePad.PreferenceTest do
  use ExUnit.Case, async: true

  alias LocalizePad.Sheet

  defp answer(source, locale) do
    [line] = Sheet.new(source, locale: locale).lines

    line.formatted || line.error
  end

  describe "converting to the reader's own units" do
    # The question this feature exists to answer: which English? The same line
    # gives a different unit to each reader, and neither is a default.
    test "the territory decides the unit" do
      assert answer("42.195 km in local units", "en-US") == "26.218757 miles"
      assert answer("42.195 km in local units", "en-AU") == "42.195 kilometres"
      assert answer("42.195 km in local units", "en-GB") == "26.218757 miles"
    end

    test "and it is the territory, not the language" do
      # `en` alone cannot answer this. That is the whole argument for carrying
      # a language tag rather than a language.
      refute answer("42.195 km in local units", "en-US") ==
               answer("42.195 km in local units", "en-AU")
    end

    test "mass follows the same rule" do
      assert answer("70 kg in local units", "en-US") == "154.323584 pounds"
      assert answer("70 kg in local units", "en-AU") == "70 kilograms"
    end

    test "temperature splits the two imperial territories" do
      # The case that proves this is CLDR data and not a metric/imperial flag:
      # Britain buys petrol by the litre, measures road distance in miles, and
      # reads temperature in Celsius.
      assert answer("25 celsius in local units", "en-US") == "77 degrees Fahrenheit"
      assert answer("25 celsius in local units", "en-GB") == "25 degrees Celsius"
      assert answer("25 celsius in local units", "en-AU") == "25 degrees Celsius"
    end
  end

  describe "word order" do
    test "the target may follow the value directly" do
      # `in lokal` is not German. The postfix form is what makes the vocabulary
      # usable in every locale rather than only in English.
      assert answer("42.195 km locally", "en-US") == "26.218757 miles"
      assert answer("70 kg lokal", "de") == "70 Kilogramm"
      assert answer("42 km 現地", "ja") == "42 キロメートル"
    end

    test "it binds as loosely as any other conversion" do
      # The whole expression to the left is the operand, so this is 42 km
      # converted once — not 40 km plus a converted 2 km.
      assert answer("40 km + 2 km locally", "en-US") == "26.09759 miles"
    end

    test "each locale has its own word for it" do
      assert answer("42 km lokal", "de") == "42 Kilometer"
      assert answer("42 km local", "fr") == "42\u00A0kilomètres"
      assert answer("42 km local", "es") == "42 kilómetros"
    end
  end

  describe "categories beyond the obvious" do
    # These needed localize 1.1.1: multi-word preferences like `:cubic_inch`
    # were converted to `"cubic_inch"`, which its own unit parser rejects, so
    # every volume and area answer came back as an error.
    test "volume, which is where the preferred unit stops being one word" do
      assert answer("2 liters in local units", "en-US") == "122.047488 cubic inches"
      assert answer("2 liters in local units", "en-AU") == "2,000 cubic centimetres"
    end

    test "area" do
      assert answer("1 hectare in local units", "en-US") == "2.471054 acres"
    end

    test "compound units keep their shape" do
      assert answer("60 km/h in local units", "en-US") == "37.282272 miles per hour"
      assert answer("60 km/h in local units", "en-AU") == "60 kilometres per hour"
    end
  end

  describe "when there is no answer" do
    test "a plain number has no units to localize" do
      # 42 of nothing is not a length, and there is no unit to prefer.
      assert {:cannot_convert, :number, {:preference, _tag}} = answer("42 locally", "en-US")
    end
  end

  describe "the word is not a keyword everywhere" do
    test "it stays prose in a locale that does not use it" do
      # `lokal` means nothing in English, and a line containing it must not
      # become a conversion — it is just a word somebody wrote.
      assert answer("42 km lokal", "en-US") == "42 kilometers"
    end
  end
end
