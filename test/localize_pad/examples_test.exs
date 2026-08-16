defmodule LocalizePad.ExamplesTest do
  use ExUnit.Case, async: true

  alias LocalizePad.{Examples, Sheet}

  doctest LocalizePad.Examples

  # The examples are the documentation, so this file is what stops the
  # documentation from quietly becoming false. An example line that no longer
  # evaluates is a claim about the product that is no longer true, and it
  # should fail the build rather than wait to be noticed by a reader.

  describe "the bundled examples" do
    test "there are some, and each names itself" do
      examples = Examples.all()

      assert length(examples) >= 5

      for example <- examples do
        assert example.title != ""
        assert example.source != ""
        assert example.locale != nil, "#{example.id} states no locale"
      end
    end

    test "every line of every example evaluates or is deliberately inert" do
      for example <- Examples.all() do
        sheet = Sheet.new(example.source, locale: example.locale)

        failures =
          sheet.lines
          |> Enum.filter(& &1.error)
          |> Enum.map(&"  line #{&1.index + 1}: #{&1.source} → #{inspect(&1.error)}")

        assert failures == [],
               "#{example.id} has lines that no longer work:\n" <> Enum.join(failures, "\n")
      end
    end

    test "every example actually computes something" do
      # A pad of nothing but prose would pass the test above and demonstrate
      # nothing at all.
      for example <- Examples.all() do
        answered =
          example.source
          |> Sheet.new(locale: example.locale)
          |> Map.fetch!(:lines)
          |> Enum.count(& &1.formatted)

        assert answered >= 5, "#{example.id} answers only #{answered} lines"
      end
    end

    test "each example round-trips through download and open" do
      # They are written in the export format, so they must survive the same
      # trip any sheet a user saves does.
      for example <- Examples.all() do
        markdown =
          example.source
          |> Sheet.new(locale: example.locale)
          |> Sheet.to_markdown()

        assert {:ok, source, locale} = Sheet.from_markdown(markdown)
        assert source == example.source, "#{example.id} does not survive a round trip"
        assert locale == example.locale
      end
    end

    test "the set covers more than one language" do
      # The point of the project is not demonstrated by six English sheets.
      locales = Examples.all() |> Enum.map(& &1.locale) |> Enum.uniq()

      assert length(locales) >= 3
      assert :en in locales
    end
  end

  describe "fetching one" do
    test "by id" do
      assert {:ok, example} = Examples.fetch("02-time")
      assert example.title == "Questions about time"
    end

    test "an id that is not an example is an error, not a file read" do
      # The id arrives from the page. Building a path out of it is how a
      # traversal starts, so it is matched against the listing instead.
      assert Examples.fetch("../../../etc/passwd") == :error
      assert Examples.fetch("nope") == :error
      assert Examples.fetch(nil) == :error
    end
  end
end
