defmodule LocalizePad.HighlightTest do
  use ExUnit.Case, async: true

  alias LocalizePad.Highlight

  doctest LocalizePad.Highlight

  defp classes(source, options \\ []) do
    source
    |> Highlight.line(Keyword.put_new(options, :locale, :en))
    |> Enum.reject(fn {class, _text} -> class == nil end)
  end

  describe "the line is reproduced exactly" do
    # The coloured layer sits behind a transparent textarea. A byte lost or
    # added anywhere shifts the text out from under the cursor, so this is the
    # invariant the whole feature rests on.
    @sources [
      "19 + 22",
      "  leading and trailing   ",
      "# Trip",
      "// a note",
      "Breakfast: $19 + 22 EUR // paid cash",
      "monthly rent = 1.900,50",
      "@1 + 20% of 3rd",
      "9am to 5pm New York",
      "100 km in miles",
      "1,2345 kilomètres",
      "100キロメートルをマイルで",
      "",
      "     ",
      "!!! ??? ///"
    ]

    test "every segment list concatenates back to its source" do
      for source <- @sources, locale <- [:en, :de, :fr, :ja] do
        rebuilt =
          source
          |> Highlight.line(locale: locale)
          |> Enum.map_join("", fn {_class, text} -> text end)

        assert rebuilt == source, "#{inspect(source)} in #{locale} became #{inspect(rebuilt)}"
      end
    end

    test "a whole sheet reproduces line for line" do
      source = Enum.join(@sources, "\n")

      rebuilt =
        source
        |> Highlight.lines(locale: :en)
        |> Enum.map_join("\n", fn segments ->
          Enum.map_join(segments, "", fn {_class, text} -> text end)
        end)

      assert rebuilt == source
    end
  end

  describe "what gets a colour" do
    test "token kinds come straight from the engine" do
      assert classes("19 + 22 kg") == [
               {:number, "19"},
               {:operator, "+"},
               {:number, "22"},
               {:unit, "kg"}
             ]
    end

    test "a heading and a comment are whole-line decisions" do
      assert classes("# Trip") == [{:heading, "# Trip"}]
      assert classes("// a note") == [{:comment, "// a note"}]
    end

    test "a comment's contents are never coloured as arithmetic" do
      # The engine deliberately ignored this text. Colouring `19 + 22` inside
      # it would claim otherwise.
      assert classes("hotel // 19 + 22") == [{:word, "hotel"}, {:comment, "// 19 + 22"}]
    end

    test "a label is dimmed rather than tokenized" do
      assert [{:label, "Breakfast: "} | rest] = classes("Breakfast: 19 + 22")
      assert {:number, "19"} in rest
    end
  end

  describe "variables" do
    test "a bound name is coloured and an unbound word is not" do
      assert classes("hotel * 3", variables: ["hotel"]) == [
               {:variable, "hotel"},
               {:operator, "*"},
               {:number, "3"}
             ]

      assert classes("hotel * 3") == [
               {:word, "hotel"},
               {:operator, "*"},
               {:number, "3"}
             ]
    end

    test "a phrase name is matched whole, as the parser matches it" do
      assert classes("monthly rent / 4", variables: ["monthly rent"]) == [
               {:variable, "monthly"},
               {:variable, "rent"},
               {:operator, "/"},
               {:number, "4"}
             ]

      # One word of a phrase name is not the name.
      assert classes("rent / 4", variables: ["monthly rent"]) == [
               {:word, "rent"},
               {:operator, "/"},
               {:number, "4"}
             ]
    end

    test "declare-before-use: a name colours only below its declaration" do
      [above, declaration, below] =
        Highlight.lines("hotel * 2\nhotel = 120\nhotel * 2", locale: :en)

      refute Enum.any?(above, fn {class, _text} -> class == :variable end)
      assert Enum.any?(declaration, fn {class, _text} -> class == :label end)
      assert Enum.any?(below, fn {class, _text} -> class == :variable end)
    end
  end

  describe "the colours are the engine's, not a second opinion" do
    test "`in` is coloured as whatever the engine read it as" do
      # A separate highlighter would colour all three the same. These are the
      # three different readings the parser actually takes.
      assert {:keyword, "in"} in classes("100 km in miles")
      assert {:keyword, "in"} in classes("12 ft + 3 in")
    end

    test "a locale change recolours the same characters" do
      # `1.234,5` is one number in German and a number, a stray comma and
      # another number in English. The colours say so.
      assert classes("1.234,5", locale: :de) == [{:number, "1.234,5"}]

      assert classes("1.234,5", locale: :en) == [
               {:number, "1.234"},
               {:operator, ","},
               {:number, "5"}
             ]
    end
  end

  describe "a name where it is bound" do
    # `classes/2` above works a single line; these need the sheet, because a
    # name only counts as bound from the line below its declaration.
    defp bound_classes(source) do
      source
      |> Highlight.lines(locale: :en)
      |> Enum.map(fn segments -> Enum.map(segments, &elem(&1, 0)) end)
    end

    test "the definition is marked, not dimmed like a label" do
      # It was sharing the muted `:label` class, which made the most useful
      # thing on the line the least visible one.
      [declaration, _use] = bound_classes("VAT = 10%\nVAT on $300")

      assert :definition in declaration
    end

    test "a multi-word name is covered whole" do
      assert [[:definition, :label, :number]] = bound_classes("monthly  rent = 550")
    end

    test "a label is still a label" do
      [segments] = bound_classes("Breakfast: 19 + 22")

      assert :label in segments
      refute :definition in segments
    end

    test "and a declared name colours as the variable the engine reads" do
      # The parser resolves a declared name over the unit dictionary, so the
      # colours have to say the same thing.
      [_declaration, use] = bound_classes("week = 5\nweek * 2")

      assert :variable in use
      refute :unit in use
    end

    test "while an undeclared one is still a unit" do
      [segments] = bound_classes("3 weeks")

      assert :unit in segments
    end
  end
end
