defmodule LocalizePad.LocalesTest do
  @moduledoc """
  French, Spanish and Japanese.

  German gets its own file because it was the locale the thesis was proved in.
  These three test what German could not: a locale whose numbers group with a
  narrow no-break space, a locale whose word for "tomorrow" is also its word for
  "morning", and a script written without spaces at all.

  """

  use ExUnit.Case, async: true

  alias LocalizePad.Sheet

  defp answer(source, locale) do
    [line] = Sheet.new(source, locale: locale).lines
    line.formatted || line.error
  end

  describe "French" do
    test "units, including the prefixed forms" do
      # CLDR puts a non-breaking space between the value and the unit in
      # French, as it does in several locales. Asserted literally.
      assert answer("1234,5 mètres en kilomètres", :fr) == "1,2345\u00A0kilomètre"
      assert answer("500 milligrammes en grammes", :fr) == "0,5\u00A0gramme"
    end

    test "the grouping separator is a narrow no-break space" do
      # U+202F. A plain ASCII space is not the French separator and does not
      # group — which is correct, and worth pinning so a later "tidy-up" of
      # this file cannot silently change what is being tested.
      assert answer("1\u202F234,5 + 1", :fr) == "1\u202F235,5"
    end

    test "percentages and dates" do
      assert answer("20 % de 700", :fr) == "140"
      assert answer("10 juin 2026 + 3 semaines", :fr) == "1 juillet 2026"
    end

    test "deictic dates" do
      {:ok, expected} = Localize.Date.to_string(Date.utc_today(), locale: :fr, format: :long)

      assert answer("aujourd'hui", :fr) == expected
    end
  end

  describe "Spanish" do
    test "units and percentages" do
      assert answer("100 kilómetros en millas", :es) == "62,137119 millas"
      assert answer("20 % de 700", :es) == "140"
    end

    test "deictic dates" do
      {:ok, today} = Localize.Date.to_string(Date.utc_today(), locale: :es, format: :long)

      {:ok, tomorrow} =
        Date.utc_today() |> Date.add(1) |> Localize.Date.to_string(locale: :es, format: :long)

      assert answer("hoy", :es) == today

      # `mañana` is both "tomorrow" and "morning". Read as the date, which is
      # the reading a calculation wants; the other needs context a single line
      # does not carry.
      assert answer("mañana", :es) == tomorrow
    end
  end

  describe "Japanese, which has no word spaces" do
    test "a whole phrase segments into units, keywords and particles" do
      assert answer("100キロメートルをマイルで", :ja) == "62.137119 マイル"
      assert answer("3メートルをフィートで", :ja) == "9.84252 フィート"
    end

    test "deictic dates" do
      {:ok, expected} = Localize.Date.to_string(Date.utc_today(), locale: :ja, format: :long)

      assert answer("今日", :ja) == expected
    end

    test "Latin text inside a Japanese sheet keeps its own boundaries" do
      # `Unicode.String.split/2` under a dictionary locale used to shatter
      # Latin runs into single characters, and single letters resolve as unit
      # abbreviations — `J` is joule, `s` is second. So "Japanese" became
      # joule-second and the line produced a *wrong answer* rather than none.
      #
      # Fixed upstream in unicode_string 2.3.1; the script-partitioning
      # workaround this test was written against is gone. The test stays,
      # because the failure it guards is the worst kind this program has —
      # a plausible answer to a question nobody asked.
      assert answer("2026-06-15 → Japanese", :ja) == "令和8年6月15日"
      assert answer("19 + 22 for breakfast", :ja) == "41"
    end

    test "mixed script in one line splits on each run's own rules" do
      # Thai has no word spaces either, and a Thai line still has to read Latin
      # unit abbreviations beside Thai prose. Asserted on the tokens rather
      # than the answer, because Thai is not one of this app's configured
      # output locales and the formatting would fall back to English.
      {:ok, tokens} = LocalizePad.Tokenizer.tokenize("สวัสดี 100 km", locale: :th)

      assert Enum.map(tokens, & &1.source) == ["สวัสดี", "100", "km"]
      assert Enum.map(tokens, & &1.kind) == [:word, :number, :unit]
    end

    test "ordinary arithmetic is unaffected" do
      assert answer("2 + 2", :ja) == "4"
    end

    test "Japanese dates are recognised, and asked about" do
      # Calendrical parses `2026年7月3日` and always could. What was missing was
      # this program ever handing it the string: candidate windows were split
      # on whitespace, and a language that writes none arrives as a single run
      # that is a date *and* a question. CJK dates are now carved out first.
      assert answer("2026年7月3日", :ja) == "2026年7月3日"
      assert answer("7月3日", :ja) == "2026年7月3日"

      assert answer("2026年7月3日は平日", :ja) == "はい"
      assert answer("2026年7月3日は何曜日", :ja) == "金曜日"
    end

    test "era years resolve against the Japanese calendar" do
      # `令和8年` is Reiwa 8. The Gregorian calendar has no idea what that means,
      # so the first parse fails and the window is offered to the calendar that
      # does. The era names are not enumerated here — CLDR knows all 236 of
      # them, and Calendrical refusing a string is a cheaper and more accurate
      # answer than a regex of every era since 645.
      assert answer("令和8年7月3日", :ja) == "2026年7月3日"
      assert answer("平成31年4月30日", :ja) == "2019年4月30日"
      assert answer("昭和39年10月10日", :ja) == "1964年10月10日"
    end

    test "an era date can be asked about like any other" do
      assert answer("令和8年7月3日は何曜日", :ja) == "金曜日"
    end

    test "the CJK date shape needs one marker, not two" do
      # The Latin rule demands two separators because `9.8` and `100/5` are
      # ambiguous with arithmetic. 年月日 are not arithmetic in any language, so
      # a single marker already settles it and demanding two would reject
      # `7月3日`, which is unambiguously a date.
      assert answer("2026 + 1", :ja) == "2,027"
      assert answer("9.8 * 2", :ja) == "19.6"
      assert answer("100 / 5", :ja) == "20"
    end
  end

  describe "every locale reads its own sheet" do
    test "the same characters mean different numbers" do
      assert answer("1.234,5 + 1", :de) == "1.235,5"
      assert answer("1,234.5 + 1", :en) == "1,235.5"
    end

    test "an operator from the wrong language is not an operator" do
      # A sheet in French is read in French. `per` is not a French word, so it
      # is prose — and the line is then not a rate.
      assert {:unsupported_operation, _op, _left, _right} = answer("99 EUR per week", :fr)
    end
  end

  describe "the words the engine writes itself" do
    # Everything else in an answer is localized because CLDR supplies it. These
    # three strings are the ones this program authors, and until they went
    # through Gettext a German sheet answered a German question in English.
    alias LocalizePad.Value

    defp summary(source, locale) do
      [line | _rest] = Sheet.new(source, locale: locale).lines

      line.formatted
    end

    test "yes and no are translated" do
      assert Value.format(true, locale: :en) == {:ok, "yes"}
      assert Value.format(true, locale: :de) == {:ok, "ja"}
      assert Value.format(true, locale: :fr) == {:ok, "oui"}
      assert Value.format(true, locale: :es) == {:ok, "sí"}
      assert Value.format(true, locale: :ja) == {:ok, "はい"}

      assert Value.format(false, locale: :de) == {:ok, "nein"}
      assert Value.format(false, locale: :ja) == {:ok, "いいえ"}
    end

    test "a truncated set names its count in the sheet's language" do
      assert summary("every Monday", :en) =~ "5 dates"
      assert summary("jeden Montag", :de) =~ "5 Termine"
      assert summary("chaque lundi", :fr) =~ "5 dates"
      assert summary("cada lunes", :es) =~ "5 fechas"
      assert summary("毎週月曜日", :ja) =~ "5件"
    end

    test "a regional locale reads its language's catalogue" do
      # Gettext does no parent-locale fallback of its own, so `de-AT` would
      # find no catalogue and answer in English unless the lookup is narrowed
      # to the language subtag.
      assert Value.format(true, locale: :"de-AT") == {:ok, "ja"}
    end

    test "an unresolvable locale falls back rather than raising" do
      # A formatter sits on the render path. Whatever arrives here, it answers.
      assert Value.format(true, locale: :"zz-junk") == {:ok, "yes"}
      assert Value.format(false, locale: nil) == {:ok, "no"}
    end

    test "the count is formatted once, by the locale, not twice" do
      # The number reaches the message already formatted, so a locale that
      # groups thousands differently still shows its own grouping and not
      # Gettext's idea of it.
      assert {:ok, formatted} = Value.format(1234, locale: :de)
      assert formatted == "1.234"
    end
  end
end
