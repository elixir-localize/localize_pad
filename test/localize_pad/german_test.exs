defmodule LocalizePad.GermanTest do
  @moduledoc """
  The localization thesis, proved in one locale.

  Everything asserted here works because CLDR already knew it: the decimal and
  grouping separators, the month names, the date field order, the unit names
  and their singular and plural forms, the percent sign's placement. The only
  thing authored for German is a page of operator words in
  `LocalizePad.Lexicon` — which is the whole claim.

  """

  use ExUnit.Case, async: true

  alias LocalizePad.{Sheet, Units}

  doctest LocalizePad.Units

  defp de(source) do
    [line] = Sheet.new(source, locale: :de).lines
    line.formatted || line.error
  end

  defp en(source) do
    [line] = Sheet.new(source, locale: :en).lines
    line.formatted || line.error
  end

  describe "numbers read and written the German way" do
    test "the separators swap meaning" do
      assert de("1.234,5 + 1") == "1.235,5"
    end

    test "and the same characters are not a number in English" do
      assert {:unexpected, ","} = en("1.234,5 + 1")
    end
  end

  describe "unit names come from CLDR, not from a table written here" do
    test "German unit names resolve on both sides of a conversion" do
      assert de("1.234,5 Meter in Kilometer") == "1,2345 Kilometer"
      assert de("100 Kilometer in Meilen") == "62,137119 Meilen"
      assert de("3 Meter zu Fuß") == "9,84252 Fuß"
    end

    test "singular and plural both resolve" do
      assert Units.resolve("Woche", :de) == {:ok, "week"}
      assert Units.resolve("Wochen", :de) == {:ok, "week"}
    end

    test "other locales come free from the same index" do
      assert Units.resolve("semaine", :fr) == {:ok, "week"}
      assert Units.resolve("semanas", :es) == {:ok, "week"}
    end

    test "a word that is not a unit stays a word" do
      assert Units.resolve("Frühstück", :de) == :error
    end

    test "the index is not consulted for English" do
      # Unity's alias table *is* the English vocabulary, and it is still
      # narrower than CLDR — 95 of the index's English display names have no
      # Unity alias, `kilocalories` and `arcminutes` among them. Consulting the
      # index for English would quietly widen the vocabulary on every English
      # sheet, which is the opposite of what a language built on "unrecognised
      # words are noise" wants.
      assert Units.resolve("kilocalories", :en) == {:ok, "kilocalorie"}
      assert en("120 * 3 kilocalories") == "360"
    end
  end

  describe "dates read and written the German way" do
    test "German date order and month names" do
      assert de("16.05.2026") == "16. Mai 2026"
      assert de("10. Juni 2026 + 3 Wochen") == "1. Juli 2026"
    end

    test "deictic dates" do
      today = Date.utc_today()
      {:ok, expected} = Localize.Date.to_string(today, locale: :de, format: :long)

      assert de("heute") == expected
    end

    test "spans" do
      assert de("7:30 bis 20:45") == "13 Stunden, 15 Minuten"
    end
  end

  describe "percentages and money" do
    test "the German percentage phrase" do
      assert de("20 % von 700") == "140"
      assert de("200 + 10 %") == "220"
    end

    test "money and rates" do
      assert de("30 EUR") == "30,00 €"
      assert de("99 EUR pro Woche") == "99,00 €/Woche"
    end
  end

  describe "what German shows about the limits" do
    test "an English operator does not work on a German sheet, and should not" do
      # `per` is not a German word. A sheet in German is read in German.
      assert {:unsupported_operation, _operator, _left, _right} = de("99 EUR per week")
    end

    test "one word cannot carry two roles" do
      # `nach` is both "in" (conversion) and "after" (relative date). German
      # keeps it for "after" and uses `in` for conversion, because the lexicon
      # maps one surface form to one role. Word *order* is the larger version
      # of the same problem and will need phrase rules per locale, not just
      # vocabulary per locale.
      assert LocalizePad.Lexicon.role("nach", :de) == {:ok, :after}
      assert LocalizePad.Lexicon.role("in", :de) == {:ok, :to}
    end
  end
end
