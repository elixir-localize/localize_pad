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

    test "and it can take an average or a median in its own language" do
      assert answer("10\n20\n30\ndurchschnitt", "de") == "20"
      assert answer("10\n20\n30\nmoyenne", "fr") == "20"
      assert answer("10\n20\n30\npromedio", "es") == "20"
      assert answer("10\n20\n30\n平均", "ja") == "20"

      assert answer("10\n20\n30\nzentralwert", "de") == "20"
      assert answer("10\n20\n30\nmédiane", "fr") == "20"
      assert answer("10\n20\n30\nmediana", "es") == "20"
      assert answer("10\n20\n30\n中央値", "ja") == "20"
    end

    test "and it can count and find its ends in its own language too" do
      assert answer("10\n20\n30\nanzahl", "de") == "3"
      assert answer("10\n20\n30\nnombre", "fr") == "3"
      assert answer("10\n20\n30\ncuenta", "es") == "3"
      assert answer("10\n20\n30\n件数", "ja") == "3"

      assert answer("10\n20\n30\nkleinster wert", "de") == "10"
      assert answer("10\n20\n30\nmáximo", "es") == "30"
      assert answer("10\n20\n30\n最小", "ja") == "10"
    end

    test "and the average and the median are one letter apart in Spanish" do
      # `media` is the average and `mediana` is the median. Two words, two
      # answers, and nothing but the last three letters to tell them apart.
      assert answer("10\n20\n60\nmedia", "es") == "30"
      assert answer("10\n20\n60\nmediana", "es") == "20"
    end

    test "and a word that totals in one language is prose in another" do
      # `somme` is French. On an English sheet it is just a word, and the line
      # above it must not be totalled by accident.
      assert answer("19\n22\nsomme", "en") == :no_expression
    end
  end

  describe "the sun and the moon in the reader's language" do
    test "each language names the events its own way" do
      # `Sonnenaufgang` is one word, `lever du soleil` is three, and `日の出`
      # is three characters the segmenter may hand back either whole or split.
      assert answer("Sonnenaufgang in Sydney am 21. Juni 2026", "de") == "06:59"
      assert answer("lever du soleil à Sydney le 21 juin 2026", "fr") == "06:59"
      assert answer("amanecer en Sídney el 21 de junio de 2026", "es") == "6:59"
      assert answer("日の出 シドニー 2026-06-21", "ja") == "6:59"
    end

    test "and the sun sets in each of them too" do
      # One sunset, four ways of asking. The clock reading is identical because
      # it is the same sun over the same city.
      assert answer("Sonnenuntergang in Tokio am 21. Juni 2026", "de") == "18:59"
      assert answer("coucher du soleil à Tokyo le 21 juin 2026", "fr") == "18:59"
      assert answer("puesta del sol en Tokio el 21 de junio de 2026", "es") == "18:59"
      assert answer("日の入り 東京 2026-06-21", "ja") == "18:59"
    end

    test "the moon rises and sets in each, including where the script has no spaces" do
      # `月の出` comes back as three tokens where `日の出` comes back as one,
      # so the unspaced line has to be searched as well as the spaced one.
      assert answer("Mondaufgang in Tokio am 21. Juni 2026", "de") != :no_expression
      assert answer("月の出 東京 2026-06-21", "ja") != :no_expression
      assert answer("月の入り 東京 2026-06-21", "ja") != :no_expression
    end

    test "and an English event word is prose on a sheet that is not English" do
      # The rule the totalling words already follow: `Summe` adds a German
      # sheet up and `sum` does not. What comes back is a refusal rather than a
      # time — which refusal is not the point, and would only pin the parser.
      refute is_binary(answer("sunrise in Tokyo on June 21, 2026", "de"))
    end
  end

  describe "an itinerary in the reader's language" do
    test "the same trip, five ways, arriving at the same arithmetic" do
      trips = [
        {"trip from March 3, 2026\n3 nights in Tokyo\n5 nights in Kyoto", "en"},
        {"Reise ab 3.3.2026\n3 Nächte in Tokio\n5 Nächte in Kyoto", "de"},
        {"voyage du 3 mars 2026\n3 nuits à Tokyo\n5 nuits à Kyoto", "fr"},
        {"viaje del 3 de marzo de 2026\n3 noches en Tokio\n5 noches en Kioto", "es"},
        {"旅程 2026-03-03\n東京: 3泊\n京都: 5泊", "ja"}
      ]

      for {source, locale} <- trips do
        assert opening(source, locale) =~ "8", "#{locale} did not total eight nights"
      end
    end

    test "a trip closes in its own language, and counts what is left in it" do
      assert opening("Reise ab 3.3.2026\n3 Nächte in Tokio\nReise endet 22.3.2026", "de") ==
               "3 Nächte, 16 übrig"

      assert opening("voyage du 3 mars 2026\n3 nuits à Tokyo\nvoyage fin 22 mars 2026", "fr") ==
               "3 nuits, 16 de libre"
    end

    # A trip reports on its opening line, where the others report on their last.
    defp opening(source, locale) do
      source
      |> Sheet.new(locale: locale)
      |> Map.fetch!(:lines)
      |> List.first()
      |> Map.get(:formatted)
    end
  end

  describe "money vocabulary in the reader's language" do
    test "a sales tax is named the way each country names it" do
      assert answer("MwSt = 19%\n300 € + MwSt", "de") == "357,00\u00A0€"
      assert answer("TVA = 20%\n300 € + TVA", "fr") == "360,00\u00A0€"
      assert answer("IVA = 21%\n300 € + IVA", "es") == "363,00\u00A0€"
      assert answer("消費税 = 10%\n¥300 + 消費税", "ja") == "￥330"
    end

    test "including the ones written as more than one token" do
      # `sales tax` is two words and `消費税` is one word the segmenter splits
      # into two. Both were in the vocabulary and neither could ever match
      # until tax names were joined over runs of words, as zone names are.
      assert answer("sales tax = 8%\n$300 + sales tax", "en") == "$324.00"
      assert answer("消費税 = 10%\n¥300 + 消費税", "ja") == "￥330"
    end

    test "a loan is repaid in the reader's words" do
      # One calculation, four vocabularies, and the same cent.
      assert answer("monthly repayment on $10,000 over 6 years at 6%", "en") == "$165.73"
      assert answer("monatliche Rate auf 10.000 € über 6 Jahre zu 6 %", "de") == "165,73\u00A0€"
      assert answer("mensualité sur 10 000 € sur 6 ans à 6 %", "fr") == "165,73\u00A0€"
      assert answer("cuota mensual de 10.000 € durante 6 años al 6 %", "es") == "165,73\u00A0€"
    end

    test "and interest is earned in them" do
      assert answer("interest on $1,000 for 3 years at 7%", "en") == "$225.04"
      assert answer("Zinsen auf 1.000 € für 3 Jahre zu 7 %", "de") == "225,04\u00A0€"
    end

    test "a present value too, one word in German and two in English" do
      assert answer("present value of $1,000 after 20 years at 10%", "en") == "$148.64"
      assert answer("Barwert von 1.000 € nach 20 Jahren zu 10 %", "de") == "148,64\u00A0€"
      assert answer("valeur actuelle de 1 000 € après 20 ans à 10 %", "fr") == "148,64\u00A0€"
    end

    test "German reads its dative plural, which is what a preposition governs" do
      # `nach 3 Jahren` is how the phrase is written; CLDR holds `Jahr` and
      # `Jahre` and has no reason to hold `Jahren`, so the natural phrasing
      # was not a duration at all. `3 Wochen` always worked, its plural
      # already ending in `-n`, which is what made the gap look arbitrary.
      assert answer("1.000 € nach 3 Jahren zu 7 %", "de") == "1.225,04\u00A0€"
      assert answer("1.000 € nach 3 Jahre zu 7 %", "de") == "1.225,04\u00A0€"
    end

    test "an approximate year is qualified in the reader's language" do
      for {line, locale} <- [
            {"circa 1955", "en"},
            {"ungefähr 1955", "de"},
            {"environ 1955", "fr"},
            {"hacia 1955", "es"},
            {"約 1955", "ja"}
          ] do
        assert answer(line, locale) =~ "1955", "#{locale} did not read #{line}"
      end
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
