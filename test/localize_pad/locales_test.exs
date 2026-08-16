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
end
