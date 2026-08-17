defmodule LocalizePad.SheetTest do
  use ExUnit.Case, async: true

  alias LocalizePad.Sheet

  doctest LocalizePad.Line
  doctest LocalizePad.Sheet
  doctest LocalizePad.Value

  defp answers(source, options \\ []) do
    source
    |> Sheet.new(Keyword.put_new(options, :locale, :en))
    |> Map.fetch!(:lines)
    |> Enum.map(& &1.formatted)
  end

  defp kinds(source) do
    source
    |> Sheet.new(locale: :en)
    |> Map.fetch!(:lines)
    |> Enum.map(& &1.kind)
  end

  describe "line classification" do
    test "recognises every kind" do
      source = """
      # Heading
      // a comment
      cost = 10
      cost * 2
      sum

      just prose
      """

      assert kinds(source) == [
               :heading,
               :comment,
               :declaration,
               :expression,
               :aggregate,
               :blank,
               :expression,
               :blank
             ]
    end

    test "a label is stripped so its digits stay out of the arithmetic" do
      assert answers("Cost of the 128 GB phone: 999") == ["999"]
    end

    test "a clock time is not mistaken for a label" do
      # The colon must be followed by whitespace to make a label, which is what
      # keeps `14:45` intact. It does not evaluate yet — clock times arrive
      # with the temporal work — but it must not be silently read as a label
      # named "14" either.
      line = LocalizePad.Line.classify(0, "14:45")

      assert line.label == nil
    end

    test "a trailing double-slash comment is ignored" do
      assert answers("19 + 22 // paid in cash") == ["41"]
    end

    test "headings and comments produce no answer" do
      assert answers("# Trip\n// note") == [nil, nil]
    end
  end

  describe "variables" do
    test "a declaration binds for the lines below" do
      assert answers("cost = 550\ncost * 2") == ["550", "1,100"]
    end

    test "phrase names work" do
      assert answers("monthly rent = 1900\nmonthly rent / 4") == ["1,900", "475"]
    end

    test "redeclaring shadows from that point on" do
      source = """
      rate = 100
      rate * 2
      rate = 200
      rate * 2
      """

      assert answers(source) == ["100", "200", "200", "400", nil]
    end

    test "a name used before it is declared is not resolved" do
      # Declare-before-use is the rule, so the first line cannot see the
      # binding made below it.
      assert answers("cost * 2\ncost = 10") == [nil, "10"]
    end
  end

  describe "line references" do
    test "a reference reads the answer of a line above" do
      assert answers("19 + 22\n@1 + 100") == ["41", "141"]
    end

    test "a reference to a line with no answer is reported, not crashed" do
      sheet = Sheet.new("# heading\n@1 + 1", locale: :en)

      assert [_heading, line] = sheet.lines
      assert line.error == {:dangling_line_reference, 1}
      assert line.formatted == nil
    end
  end

  describe "totals and subtotals" do
    test "the total adds up expression lines" do
      assert Sheet.total(Sheet.new("19\n22\n1", locale: :en)) == 42
    end

    test "declarations are excluded so their value is not counted twice" do
      # Were the declaration counted, this would total 30 rather than 20.
      assert Sheet.total(Sheet.new("cost = 10\ncost\ncost", locale: :en)) == 20
    end

    test "a subtotal sums back to the previous heading" do
      source = """
      # Food
      19
      22
      sum
      # Travel
      100
      sum
      """

      assert answers(source) == [nil, "19", "22", "41", nil, "100", "100", nil]
    end

    test "a subtotal sums back to the previous subtotal" do
      assert answers("10\n20\nsum\n5\nsum") == ["10", "20", "30", "5", "5"]
    end

    test "an average divides the sum by the entries it covers" do
      assert answers("19\n22\naverage") == ["19", "22", "20.5"]
    end

    test "and `mean` is the same function under another name" do
      assert answers("19\n22\nmean") == ["19", "22", "20.5"]
    end

    test "a median of an odd count is the middle entry, in order rather than in place" do
      assert answers("30\n10\n20\nmedian") == ["30", "10", "20", "20"]
    end

    test "and of an even count, the mean of the two either side" do
      assert answers("1\n2\n3\n4\nmedian") == ["1", "2", "3", "4", "2.5"]
    end

    test "a quantity that will not add refuses the total rather than being skipped" do
      # Skipping it would answer `41` for a sheet whose middle line is a
      # distance, under a label reading `Total`. There is no total of a number
      # and a distance, so there is no answer.
      assert Sheet.total(Sheet.new("19\n3 meters\n22", locale: :en)) == nil
    end

    test "and so does a quantity of the wrong kind" do
      # Both are quantities and neither can be added to the other. The old
      # behaviour kept whichever came first and reported it as the total of
      # the page, in that line's own unit.
      assert Sheet.total(Sheet.new("3 meters\n100 kg", locale: :en)) == nil
    end

    test "and a mix of shapes, whichever two" do
      assert Sheet.total(Sheet.new("19\n$3", locale: :en)) == nil
      assert Sheet.total(Sheet.new("3 meters\n$3", locale: :en)) == nil
    end

    test "but compatible units still total, converted into the first" do
      total = Sheet.total(Sheet.new("1 meter\n50 cm", locale: :en))

      assert Localize.Unit.to_string!(total, locale: :en) == "1.5 meters"
    end
  end

  describe "several functions over one block" do
    test "each answers for the entries the run follows, not for the line above it" do
      # Read as a boundary, the `sum` above would leave `average` and `median`
      # with nothing to report on and two blank answers where the sheet asked
      # two questions.
      assert answers("10\n20\n30\nsum\naverage\nmedian") ==
               ["10", "20", "30", "60", "20", "20"]
    end

    test "a blank line inside the run does not break it" do
      # A blank separates nothing anywhere else in a sheet — only a heading or
      # a function bounds a block.
      assert answers("10\n20\nsum\n\naverage") == ["10", "20", "30", nil, "15"]
    end

    test "and the run still stops at a heading" do
      source = """
      # Food
      19
      22
      sum
      average
      # Travel
      100
      median
      """

      assert answers(source) == [nil, "19", "22", "41", "20.5", nil, "100", "100", nil]
    end

    test "an entry below the run belongs to the next block, not the last one" do
      assert answers("10\n20\nsum\naverage\n5\nsum") ==
               ["10", "20", "30", "15", "5", "5"]
    end
  end

  describe "quantities average and order in one unit" do
    test "the average converts, and answers in the first entry's unit" do
      assert answers("1 meter\n50 cm\naverage") == ["1 meter", "50 centimeters", "0.75 meters"]
    end

    test "and so does the median, which orders by size rather than by line" do
      # 50 cm is the smallest of the three however early it is written.
      assert answers("1 meter\n50 cm\n2 m\nmedian") ==
               ["1 meter", "50 centimeters", "2 meters", "1 meter"]
    end

    test "quantities of different kinds have no average" do
      assert answers("3 meters\n100 kg\naverage") == ["3 meters", "100 kilograms", nil]
    end

    test "and no median" do
      assert answers("3 meters\n100 kg\nmedian") == ["3 meters", "100 kilograms", nil]
    end

    test "a value that was never a candidate is left out of the count as well as the sum" do
      # Counted, the date would divide 41 by three and answer 13.67 for a page
      # holding two numbers.
      assert answers("19\nApril 12, 2026\n22\naverage") ==
               ["19", "April 12, 2026", "22", "20.5"]
    end
  end

  describe "money totals" do
    # `Money.sum/2` takes the rates, so a sheet's total can be checked against
    # known ones rather than whatever the retriever last fetched.
    @rates %{
      EUR: Decimal.new(1),
      USD: Decimal.new("1.1"),
      AUD: Decimal.new("1.7"),
      GBP: Decimal.new("0.85")
    }

    test "one currency needs no rate and stays in the currency written" do
      total = Sheet.total(Sheet.new("$240\n$89\n$120", locale: :en), %{})

      assert Money.equal?(total, Money.new(:USD, "449.00"))
    end

    test "and money averages and orders in it too, still needing no rate" do
      # The average keeps the currency's own two places: `449 / 3` is rounded
      # for display rather than reported as a repeating fraction.
      assert answers("$240\n$89\n$120\nmedian\naverage") ==
               ["$240.00", "$89.00", "$120.00", "$120.00", "$149.67"]
    end

    test "several currencies are converted into the reader's own" do
      # 100 EUR is 170 AUD and 11 USD is another 17.
      sheet = Sheet.new("100 EUR\n11 USD", locale: "en-AU")

      assert Money.equal?(Sheet.total(sheet, @rates), Money.new(:AUD, 187))
    end

    test "and the reader's own is what changes the answer, not the sheet" do
      # The same two lines, read by someone else. `Money.sum/2` would report
      # both in euros, the topmost line's currency, which is an accident of
      # how the sheet was typed.
      sheet = Sheet.new("100 EUR\n11 USD", locale: "en-GB")

      assert Money.equal?(Sheet.total(sheet, @rates), Money.new(:GBP, "93.50"))
    end

    test "a currency with no rate has no total" do
      sheet = Sheet.new("100 EUR\n20 USD", locale: "en-AU")

      assert Sheet.total(sheet, %{}) == nil
    end

    test "a line built from another line refuses the total rather than counting it twice" do
      # `@1 + 100` already contains the 41. Adding both reports 182 for a sheet
      # whose independent answers come to 141 — or to 41, depending on which
      # line you consider the real one, which is the reason there is no answer.
      assert Sheet.total(Sheet.new("19 + 22\n@1 + 100", locale: :en)) == nil
    end

    test "and it follows the chain, not just the single step" do
      # The declaration in the middle is not counted, so only the transitive
      # closure shows that line 1's answer is inside line 3.
      assert Sheet.total(Sheet.new("19 + 22\ntotal = @1\ntotal + 5", locale: :en)) == nil
    end

    test "but a declaration is not double counted, because it is never counted" do
      # `hotel` is an input to line 2 and has no answer of its own in the
      # total, so reusing it costs nothing.
      assert Sheet.total(Sheet.new("hotel = 120\nhotel * 3\n50", locale: :en)) == 410
    end

    test "and neither is a subtotal" do
      assert Sheet.total(Sheet.new("10\n20\nsum", locale: :en)) == 30
    end

    test "and a value that was never a candidate is passed over" do
      # A date is not a competing total. Its presence on the page does not stop
      # the numbers from having one.
      assert Sheet.total(Sheet.new("19\nApril 12, 2026\n22", locale: :en)) == 41
    end
  end

  describe "the dependency graph" do
    test "tracks variable dependencies" do
      sheet = Sheet.new("cost = 10\ncost * 2\ncost + 1", locale: :en)

      assert Sheet.dependents(sheet, 0) == [1, 2]
    end

    test "tracks line reference dependencies transitively" do
      sheet = Sheet.new("10\n@1 * 2\n@2 * 2", locale: :en)

      assert Sheet.dependents(sheet, 0) == [1, 2]
    end

    test "a subtotal depends on every line it covers" do
      sheet = Sheet.new("10\n20\nsum", locale: :en)

      assert Sheet.dependents(sheet, 0) == [2]
      assert Sheet.dependents(sheet, 1) == [2]
    end

    test "an unrelated line is not a dependent" do
      sheet = Sheet.new("cost = 10\n99 + 1\ncost * 2", locale: :en)

      assert Sheet.dependents(sheet, 0) == [2]
    end
  end

  describe "editing" do
    test "replacing a line re-evaluates what depended on it" do
      sheet = Sheet.new("cost = 10\ncost * 2", locale: :en)
      assert Enum.map(sheet.lines, & &1.formatted) == ["10", "20"]

      sheet = Sheet.put_line(sheet, 0, "cost = 50")
      assert Enum.map(sheet.lines, & &1.formatted) == ["50", "100"]
    end

    test "an out-of-range index leaves the sheet alone" do
      sheet = Sheet.new("2 + 2", locale: :en)

      assert Sheet.put_line(sheet, 99, "nope") == sheet
    end

    test "source round-trips" do
      source = "# Trip\ncost = 10\ncost * 2"

      assert source |> Sheet.new(locale: :en) |> Sheet.to_source() == source
    end
  end

  describe "Markdown export" do
    test "answers are written as the sheet's own comment syntax" do
      markdown = "19 + 22" |> Sheet.new(locale: :en) |> Sheet.to_markdown()

      assert markdown =~ "19 + 22   // 41"
    end

    test "the export round-trips" do
      # A download is a save, and a save that cannot be reopened is a
      # screenshot. `//` is the sheet's own marker for text the engine ignores,
      # so the exported block pastes straight back in.
      original = "# Trip\n\n19 + 22\nhotel = 120\nhotel * 3"
      markdown = original |> Sheet.new(locale: :en) |> Sheet.to_markdown()

      block = markdown |> String.split("```") |> Enum.at(1) |> String.trim()
      reimported = Sheet.new(block, locale: :en)

      assert Enum.map(reimported.lines, & &1.formatted) ==
               original
               |> Sheet.new(locale: :en)
               |> Map.fetch!(:lines)
               |> Enum.map(& &1.formatted)
    end

    test "the locale is recorded, because it decides what the numbers mean" do
      assert "1.234,5" |> Sheet.new(locale: :de) |> Sheet.to_markdown() =~ "Locale: `de`"
      assert "1,234.5" |> Sheet.new(locale: :en) |> Sheet.to_markdown() =~ "Locale: `en`"
    end

    test "a set is exported whole, not as the margin's summary" do
      markdown = "every Friday the 13th" |> Sheet.new(locale: :en) |> Sheet.to_markdown()

      # The margin truncates because it has one line. A file does not.
      refute markdown =~ "…"
      refute markdown =~ "5 dates"
      assert markdown =~ "Jul 13, 2029"
    end

    test "lines with no answer keep their text and gain no comment" do
      markdown = "# Trip\n\njust a note" |> Sheet.new(locale: :en) |> Sheet.to_markdown()

      assert markdown =~ "# Trip"
      assert markdown =~ "just a note"
      refute markdown =~ "just a note   //"
    end

    test "the total is included when there is one" do
      assert "19\n22" |> Sheet.new(locale: :en) |> Sheet.to_markdown() =~ "**Total:** 41"
      refute "# only a heading" |> Sheet.new(locale: :en) |> Sheet.to_markdown() =~ "Total"
    end
  end

  describe "Markdown import" do
    test "an export round-trips exactly" do
      original = "# Trip\n\nBreakfast: 19 + 22\nhotel = 120\nhotel * 3\n// a note\nsum"
      markdown = original |> Sheet.new(locale: :en) |> Sheet.to_markdown()

      assert {:ok, ^original, locale} = Sheet.from_markdown(markdown)
      assert to_string(locale) == "en"
    end

    test "importing and exporting again does not accumulate" do
      # The exporter aligns each answer into a `//` column. Keeping those on
      # the way in would mean the next export wrote `// 41   // 41`, and the
      # one after that a third time.
      original = "hotel = 120\nhotel * 3"

      cycle = fn source ->
        {:ok, back, locale} =
          source |> Sheet.new(locale: :en) |> Sheet.to_markdown() |> Sheet.from_markdown()

        {back, locale}
      end

      assert {once, _locale} = cycle.(original)
      assert {twice, _locale} = cycle.(once)
      assert once == original
      assert twice == original
    end

    test "a comment somebody wrote survives" do
      original = "19 + 22 // paid cash"
      markdown = original |> Sheet.new(locale: :en) |> Sheet.to_markdown()

      assert {:ok, ^original, locale} = Sheet.from_markdown(markdown)
      assert to_string(locale) == "en"
    end

    test "a file with no fence is taken whole" do
      assert Sheet.from_markdown("2 + 2\n3 * 3") == {:ok, "2 + 2\n3 * 3", nil}
    end

    test "a file naming no locale states none, rather than guessing one" do
      # The caller keeps whatever locale it already had. Guessing would change
      # what the numbers mean.
      assert {:ok, _source, nil} = Sheet.from_markdown("19 + 22")
    end

    test "unreadable input is an error, never a crash" do
      # Upload is untrusted: this is handed whatever file was picked.
      assert Sheet.from_markdown("") == {:error, :empty}
      assert Sheet.from_markdown("   \n  \n") == {:error, :empty}
      assert Sheet.from_markdown(nil) == {:error, :empty}
      assert Sheet.from_markdown(<<0, 1, 2, 255>>) != :crashed
    end

    test "a locale the file names but this app cannot validate is ignored" do
      assert {:ok, "19 + 22", nil} = Sheet.from_markdown("Locale: `zz-junk`\n\n```\n19 + 22\n```")
    end
  end

  describe "the same sheet read in two locales" do
    # The point of the whole project: the locale decides how the text is
    # *read*, not merely how the answer is written. These two runs are the same
    # characters producing genuinely different arithmetic.
    test "the same characters are a number in one locale and nonsense in another" do
      source = "1.234,5 + 1"

      # German reads `.` as the grouping separator and `,` as the decimal
      # point, so this is 1234.5 + 1.
      assert answers(source, locale: :de) == ["1.235,5"]

      # English reads `.` as the decimal point, which leaves a stray comma the
      # expression cannot use. Refusing is right: silently reinterpreting the
      # separators would invent an answer the user did not write.
      sheet = Sheet.new(source, locale: :en)
      assert [line] = sheet.lines
      assert line.formatted == nil
      assert line.error == {:unexpected, ","}
    end

    test "the answer is written in the locale that read it" do
      assert answers("1234567 + 0.5", locale: :en) == ["1,234,567.5"]
      assert answers("1234567 + 0,5", locale: :de) == ["1.234.567,5"]
    end

    test "unit names are localized in the answer" do
      assert answers("3 meters", locale: :en) == ["3 meters"]
      assert answers("3 meters", locale: :de) == ["3 Meter"]

      # French puts a non-breaking space between the value and the unit, per
      # CLDR. Asserting the literal codepoint keeps a future "tidy-up" from
      # quietly replacing it with an ordinary space.
      assert answers("3 meters", locale: :fr) == ["3 mètres"]
    end
  end

  describe "the three readings of `in`" do
    # `in` is the conversion keyword, the unit `inch`, and an ordinary English
    # preposition. Nothing before evaluation can tell them apart, because all
    # three parse — so a wrong guess is retried once the units disagree.
    test "an operand after it makes it the conversion keyword" do
      assert answers("100 km in miles") == ["62.137119 miles"]
    end

    test "nothing after it makes it the unit" do
      assert answers("12 ft + 3 in") == ["12.25 feet"]
      assert answers("3 in") == ["3 inches"]
    end

    test "prose after it still makes it the unit when the units agree" do
      assert answers("12 ft + 3 in total") == ["12.25 feet"]
    end

    test "prose after it makes it prose when the units do not agree" do
      # The tempting answer here is 22 inches, which is worse than refusing:
      # a sentence about money would silently acquire a length.
      assert answers("19 + 22 in cash") == ["41"]
      assert answers("$19 for breakfast + $22 in tips") == ["$41.00"]
    end

    test "it is never the unit in a position where no number precedes it" do
      # `in 3 weeks` once answered "3 inch-weeks" — a wrong answer, not a
      # refusal, and the reader had to know the answer already to catch it.
      sheet = Sheet.new("in 3 weeks", locale: :en)

      assert [line] = sheet.lines
      assert line.formatted == nil
      assert line.error == {:unexpected, "in"}
    end

    test "a genuine unit mismatch is still reported rather than retried away" do
      sheet = Sheet.new("3 m + 4 kg", locale: :en)

      assert [line] = sheet.lines
      assert line.formatted == nil
      assert line.error != nil
    end
  end

  describe "robustness" do
    test "an empty sheet does not crash" do
      assert Sheet.new("", locale: :en).lines |> Enum.map(& &1.kind) == [:blank]
    end

    test "malformed lines carry an error and leave the rest of the sheet working" do
      sheet = Sheet.new("2 +\n19 + 22", locale: :en)

      assert [broken, working] = sheet.lines
      assert broken.error != nil
      assert broken.formatted == nil
      assert working.formatted == "41"
    end

    test "a sheet of pure prose evaluates to nothing at all" do
      assert answers("thinking about the weekend\nmaybe go to the beach") == [nil, nil]
    end
  end
end
