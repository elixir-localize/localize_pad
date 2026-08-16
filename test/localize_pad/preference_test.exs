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

  describe "saying what the quantity is for" do
    # The usage is the other half of what CLDR needs. The territory alone says
    # an American measures length in feet; the usage is what turns 1.8 m into
    # `5 feet and 10.87 inches` rather than `5.91 feet`.
    test "a height is written the way heights are written" do
      assert answer("1.8 m in local height units", "en-US") == "5 feet and 10.866142 inches"
      assert answer("1.8 m in local height units", "en-AU") == "180 centimetres"
    end

    test "a body weight, which is where Britain parts company with America" do
      assert answer("70 kg in local weight units", "en-GB") == "11 stone and 5.177336 ounces"
      assert answer("70 kg in local weight units", "en-US") == "154.323584 pounds"
    end

    test "a drink" do
      assert answer("2 liters in local fluid units", "en-US") == "2.113376 quarts"
      assert answer("2 liters in local fluid units", "en-GB") == "70.390159 fluid ounces"
    end

    test "each locale names its own usages" do
      # `1,8` with a comma, because this is a German sheet — a dot there is a
      # thousands separator and the line would be about eighteen metres.
      assert answer("1,8 m in lokale Größe", "de") == "180 Zentimeter"
    end

    test "a usage word only counts directly after the preference word" do
      # `height` is a name somebody will want for a variable, and a calculator
      # whose vocabulary quietly claimed it would break more sheets than the
      # feature is worth. This is the test that pins that promise.
      [declaration, use] =
        Sheet.new("height = 1.8 m\nheight * 2", locale: "en-US").lines

      assert declaration.formatted == "1.8 meters"
      assert use.formatted == "3.6 meters"
    end

    test "and an unknown usage word is left as prose" do
      assert answer("42 km in local nonsense units", "en-US") == "26.09759 miles"
    end
  end

  describe "showing every answer in the reader's units" do
    defp shown(source, options) do
      [line] = Sheet.new(source, options).lines

      line.formatted
    end

    test "off by default, because a sheet says what its author wrote" do
      assert shown("42.195 km", locale: "en-US") == "42.195 kilometers"
    end

    test "on, every quantity is rewritten for the reader" do
      assert shown("42.195 km", locale: "en-US", prefer_local: true) == "26.218757 miles"
      assert shown("70 kg", locale: "en-US", prefer_local: true) == "154.323584 pounds"
      assert shown("42.195 km", locale: "en-AU", prefer_local: true) == "42.195 kilometres"
    end

    test "but a line that named its own unit keeps it" do
      # `3 meters to feet` asked for feet. Answering in metres because the
      # reader is Australian would override the question with a preference,
      # which is the opposite of what the setting is for.
      assert shown("3 meters to feet", locale: "en-AU", prefer_local: true) == "9.84252 feet"
    end

    test "it is display only, so the value is untouched" do
      # The running total and every `@n` reference still work on what the sheet
      # computed, not on what the margin shows.
      sheet = Sheet.new("42.195 km", locale: "en-US", prefer_local: true)
      [line] = sheet.lines

      assert line.formatted == "26.218757 miles"
      assert line.value.name == "kilometer"
    end

    test "and it leaves everything that is not a unit alone" do
      assert shown("$19 + $22", locale: "en-US", prefer_local: true) == "$41.00"
      assert shown("19 + 22", locale: "en-US", prefer_local: true) == "41"
    end
  end

  describe "when there is no answer" do
    test "a plain number has no units to localize" do
      # 42 of nothing is not a length, and there is no unit to prefer.
      assert {:cannot_convert, :number, {:preference, _tag, _usage}} =
               answer("42 locally", "en-US")
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
