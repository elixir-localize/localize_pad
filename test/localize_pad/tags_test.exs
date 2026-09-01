defmodule LocalizePad.TagsTest do
  use ExUnit.Case, async: true

  alias LocalizePad.{Highlight, Line, Sheet}

  defp answers(source) do
    source
    |> String.trim_trailing()
    |> Sheet.new(locale: :en)
    |> Map.fetch!(:lines)
    |> Enum.map(& &1.formatted)
  end

  defp answer(source), do: source |> answers() |> List.last()

  describe "tagging a line" do
    test "a tag is lifted out before the line is read, so the arithmetic is untouched" do
      assert answers("19 + 22 #food") == ["41"]
    end

    test "and the label survives it" do
      line = Line.classify(0, "Calamari: 18 #ann")

      assert {line.kind, line.label, line.expression, line.tags} ==
               {:expression, "Calamari", "18", ["ann"]}
    end

    test "a line may carry several" do
      assert Line.classify(0, "18 #ann #food").tags == ["ann", "food"]
    end

    test "case is not part of a tag, and neither is writing it twice" do
      assert Line.classify(0, "18 #Ann #ann #ANN").tags == ["ann"]
    end

    test "a tag may be written in any script" do
      assert Line.classify(0, "500 yen #食費").tags == ["食費"]
    end

    test "a `#` starting a line is still a heading, and carries no tag" do
      line = Line.classify(0, "#food")

      assert {line.kind, line.tags} == {:heading, []}
    end

    test "and a `#` inside a comment is part of the comment" do
      line = Line.classify(0, "// remember #food")

      assert {line.kind, line.tags} == {:comment, []}
    end
  end

  describe "summing a tag" do
    @bill """
    # Dinner
    Calamari: 18 #ann
    Bread: 9 #bob
    Olives: 12 #ann #shared
    Steak: 42 #ann
    Pasta: 28 #bob
    """

    test "adds up the lines carrying it, and nothing else" do
      assert answer(@bill <> "sum #ann") == "72"
      assert answer(@bill <> "sum #bob") == "37"
    end

    test "every function works on a tag, not just the sum" do
      assert answer(@bill <> "count #ann") == "3"
      assert answer(@bill <> "average #ann") == "24"
      assert answer(@bill <> "median #ann") == "18"
      assert answer(@bill <> "min #ann") == "12"
      assert answer(@bill <> "max #ann") == "42"
    end

    test "naming several tags narrows rather than widens" do
      # What Ann spent on the shared plate, not everything either word touches.
      assert answer(@bill <> "sum #ann #shared") == "12"
    end

    test "a tag nothing carries has no answer, rather than an answer of zero" do
      # Zero would be a claim that the sheet holds nothing under that tag. It
      # more often means the tag is a typo.
      assert answer(@bill <> "sum #carol") == nil
    end

    test "several tagged aggregates each see the whole section" do
      # A block boundary between them would leave the second reporting on what
      # the first had already passed.
      assert answers(@bill <> "sum #ann\nsum #bob\nsum #ann") |> Enum.take(-3) ==
               ["72", "37", "72"]
    end

    test "and an aggregate is never counted into another one" do
      # `sum #ann` carries `#ann` itself. Counted, the second would double it.
      assert answers(@bill <> "sum #ann\nsum #ann") |> Enum.take(-2) == ["72", "72"]
    end

    test "a tagged line still counts in the block's own total" do
      # A tag is something written *about* a line, not something taken out of
      # it. 18 + 9 + 12 + 42 + 28.
      assert answer(@bill <> "sum") == "109"
    end
  end

  describe "a heading ends a tag's reach" do
    @trip """
    # Rome
    lunch: 30 #food
    museum: 20 #culture
    sum #food

    # Paris
    dinner: 60 #food
    sum #food
    """

    test "so one tag means one thing per section" do
      assert answers(@trip) |> Enum.reject(&is_nil/1) == ["30", "20", "30", "60", "60"]
    end

    test "and a total under its own heading sees the section it is in" do
      # The consequence of the rule, stated as a test so it cannot surprise
      # anyone twice: tagged lines and the line totalling them belong under
      # one heading.
      assert answer(@trip <> "\n# The damage\nsum #food") == nil
    end
  end

  describe "tags and the shapes a sheet holds" do
    test "money adds up under a tag" do
      source = """
      # Trip
      hotel: $240 #lodging
      flight: $89 #travel
      taxi: $35 #travel
      sum #travel
      """

      assert answer(source) == "$124.00"
    end

    test "and quantities convert as they would anywhere else" do
      source = """
      # Walking
      morning: 3 km #walk
      evening: 500 m #walk
      sum #walk
      """

      assert answer(source) == "3.5 kilometers"
    end

    test "a tag on a declaration is not counted, because a declaration is not" do
      # Its value reaches the total through the lines that use it, and counting
      # both would put it in twice.
      source = """
      # Costs
      hotel = 120 #travel
      hotel * 2 #travel
      sum #travel
      """

      assert answer(source) == "240"
    end
  end

  describe "tags in the editor" do
    test "are coloured as the names the reader invented" do
      assert Highlight.line("Calamari: 18 #ann", locale: :en) ==
               [{:label, "Calamari: "}, {:number, "18"}, {nil, " "}, {:tag, "#ann"}]
    end

    test "including on an aggregate line" do
      assert Highlight.line("sum #ann", locale: :en) == [{nil, "sum "}, {:tag, "#ann"}]
    end

    test "but a heading is a heading all the way across" do
      assert Highlight.line("# Starters", locale: :en) == [{:heading, "# Starters"}]
    end
  end
end
