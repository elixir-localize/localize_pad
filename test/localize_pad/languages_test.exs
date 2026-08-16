defmodule LocalizePad.LanguagesTest do
  use ExUnit.Case, async: true

  alias LocalizePad.Sheet

  # The sheet is read in the reader's language, so every claim here is written
  # the way somebody who speaks it would write it. A test that exercises
  # German with English input proves nothing about German.
  defp answer(source, locale) do
    last = source |> Sheet.new(locale: locale) |> Map.fetch!(:lines) |> List.last()

    last.formatted || last.error
  end

  describe "a declared name beats the unit dictionary" do
    # Outside English the commonest words *are* units, so naming a variable
    # after an everyday noun collided with the vocabulary and the declaration
    # silently lost. `año = 12` then `año * 2` answered "2 años".
    test "in every language we ship" do
      assert answer("año = 12\naño * 2", "es") == "24"
      assert answer("Jahr = 12\nJahr * 2", "de") == "24"
      assert answer("Tag = 8\nTag * 5", "de") == "40"
      assert answer("semaine = 5\nsemaine * 2", "fr") == "10"
      assert answer("heure = 60\nheure * 3", "fr") == "180"
    end

    test "including English, where it is easier to miss" do
      assert answer("week = 5\nweek * 2", "en") == "10"
    end

    test "and a name nobody declared is still a unit" do
      # French puts a no-break space between the number and its unit.
      assert answer("3 semaines", "fr") == "3\u00A0semaines"
      assert answer("3 weeks", "en") == "3 weeks"
    end
  end

  describe "Japanese puts its particles after the operand" do
    # `の` is a genitive: `700の20%` is "700's 20%", so the whole comes first
    # where English puts it last. Read in English order it was refused, and
    # `1日あたり100` — "100 per day" — answered 0.01.
    test "the genitive reads as `of`, with the operands the other way round" do
      assert answer("700の20%", "ja") == "140"
    end

    test "and `per` likewise" do
      assert answer("1日あたり100", "ja") == "100"
      assert answer("1週間ごと100", "ja") == "100"
    end

    test "while `を` needs no swap, sitting where English puts `to`" do
      assert answer("100キロメートルをマイル", "ja") == "62.137119 マイル"
    end
  end

  describe "a sheet can add itself up in its own language" do
    test "the totalling word is the reader's" do
      assert answer("19 + 22\n120\nsumme", "de") == "161"
      assert answer("19 + 22\n120\nsomme", "fr") == "161"
      assert answer("19 + 22\n120\nsuma", "es") == "161"
      assert answer("19 + 22\n120\nsum", "en") == "161"
    end

    test "including the subtotal form" do
      assert answer("19\n22\nzwischensumme", "de") == "41"
      assert answer("19\n22\nsous-total", "fr") == "41"
    end

    test "and a word that totals in one language is prose in another" do
      # `somme` is French. On an English sheet it is just a word, and the line
      # above it must not be totalled by accident.
      assert answer("19\n22\nsomme", "en") == :no_expression
    end
  end

  describe "the core of the language works in each" do
    # Not exhaustive — a regression net across the capabilities most likely to
    # break when the locale changes, written natively in each.
    test "German" do
      assert answer("1.234,5 + 1", "de") == "1.235,5"
      assert answer("20 % von 700", "de") == "140"
      assert answer("3 Meter in Fuß", "de") == "9,84252 Fuß"
      assert answer("16.05.2026 + 3 Wochen", "de") == "6. Juni 2026"
      assert answer("ist der 3. Juli 2026 ein Werktag", "de") == "ja"
    end

    test "French" do
      assert answer("1234,5 + 1", "fr") == "1 235,5"
      assert answer("20 % de 700", "fr") == "140"
      assert answer("3 mètres en pieds", "fr") == "9,84252 pieds"
      assert answer("10 juin 2026 + 3 semaines", "fr") == "1 juillet 2026"
    end

    test "Spanish" do
      # Spanish omits the group separator at four digits, which is CLDR's
      # `minimumGroupingDigits` and not a missing separator.
      assert answer("1.234,5 + 1", "es") == "1235,5"
      assert answer("20 % de 700", "es") == "140"
      assert answer("3 metros a pies", "es") == "9,84252 pies"
    end

    test "Japanese" do
      assert answer("2026年7月3日は平日", "ja") == "はい"
      assert answer("42 km 現地", "ja") == "42 キロメートル"
    end
  end
end
