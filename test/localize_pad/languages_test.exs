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

  describe "vocabulary CLDR supplies rather than us" do
    alias LocalizePad.Lexicon
    alias LocalizePad.Temporal.Zones

    test "relative day names, including ones never authored" do
      # `übermorgen` and `vorgestern` were not in the hand table at all. They
      # arrive because the words are read from CLDR rather than transcribed.
      assert Lexicon.deictic("übermorgen", :de) == {:ok, :day_after_tomorrow}
      assert Lexicon.deictic("vorgestern", :de) == {:ok, :day_before_yesterday}
      assert Lexicon.deictic("aujourd’hui", :fr) == {:ok, :today}
      assert Lexicon.deictic("明日", :ja) == {:ok, :tomorrow}
    end

    test "and they resolve to the days they name" do
      today = Date.utc_today()

      assert answer("übermorgen", "de") ==
               Localize.Date.to_string!(Date.add(today, 2), locale: "de", format: :long)

      assert answer("vorgestern", "de") ==
               Localize.Date.to_string!(Date.add(today, -2), locale: "de", format: :long)
    end

    test "spelled ordinals come from the locale's own rule sets" do
      # German inflects its ordinals, and CLDR carries every case. The hand
      # table listed eighteen forms; generation finds more.
      german = Lexicon.recurrence(:de).ordinals

      assert german["erste"] == 1
      assert german["ersten"] == 1
      assert german["erster"] == 1
      assert german["erstes"] == 1
      assert map_size(german) > 18
    end

    test "but `last` stays authored, being a position and not an ordinal" do
      assert Lexicon.recurrence(:de).ordinals["letzte"] == -1
      assert Lexicon.recurrence(:en).ordinals["last"] == -1
    end

    test "the day-of-week phrase is CLDR's own field name" do
      assert ["wochentag"] in Lexicon.recurrence(:de).day_of_week
      assert ["jour", "semaine"] in Lexicon.recurrence(:fr).day_of_week
    end

    test "zone city names are the locale's" do
      assert {:ok, %Zones{name: "Asia/Tokyo"}} = Zones.resolve("Tokio", :de)
      assert {:ok, %Zones{name: "Europe/London"}} = Zones.resolve("Londres", :fr)
      assert {:ok, %Zones{name: "America/New_York"}} = Zones.resolve("Nueva York", :es)
      assert {:ok, %Zones{name: "Asia/Tokyo"}} = Zones.resolve("東京", :ja)
    end

    test "and the identifier's name still works in any locale" do
      # Half the world's software prints the IANA name; a German sheet must
      # not stop understanding it.
      assert {:ok, %Zones{name: "Asia/Tokyo"}} = Zones.resolve("Tokyo", :de)
    end

    test "a country names a zone only where it has one" do
      assert {:ok, %Zones{name: "Asia/Tokyo"}} = Zones.resolve("Japan", :de)
      assert {:ok, %Zones{name: "Asia/Tokyo"}} = Zones.resolve("Japon", :fr)
      assert {:ok, %Zones{name: "Europe/Paris"}} = Zones.resolve("France", :en)

      # The United States has twenty-nine, so its name says nothing about which.
      assert Zones.resolve("Vereinigte Staaten", :de) == :error
    end
  end

  describe "ordinals come from the locale's rule sets, so the paradigm comes with them" do
    defp dates(source, locale) do
      [line] = Sheet.new(source, locale: locale).lines

      line.formatted
    end

    test "German reads an ordinal in any case it is written in" do
      # Nominative, accusative and dative. The ending changes, the answer does
      # not — and none of these forms is written down anywhere in the pad.
      answer = dates("jeden ersten Montag", :de)

      assert answer != nil
      assert dates("jeder erste Montag", :de) == answer
      assert dates("jedem ersten Montag", :de) == answer
    end

    test "and the same holds further up the ordinals" do
      answer = dates("jeden zweiten Freitag", :de)

      assert answer != nil
      assert dates("jedem zweiten Freitag", :de) == answer
      assert dates("jeder zweite Freitag", :de) == answer
    end

    test "French reads the singular and the plural alike" do
      answer = dates("quatrième jeudi de novembre", :fr)

      assert answer != nil
      assert dates("quatrièmes jeudi de novembre", :fr) == answer
    end

    test "and treats `second` as the synonym for `deuxième` that it is" do
      # This pair is the exception the rule sets cannot supply: `second` is a
      # different word rather than a form of `deuxième`, so it is authored.
      answer = dates("chaque deuxième mardi", :fr)

      assert answer != nil
      assert dates("chaque second mardi", :fr) == answer
    end
  end
end
