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
          |> Enum.filter(&(&1.error && not tolerated?(&1.error)))
          |> Enum.map(&"  line #{&1.index + 1}: #{&1.source} → #{inspect(&1.error)}")

        assert failures == [],
               "#{example.id} has lines that no longer work:\n" <> Enum.join(failures, "\n")
      end
    end

    # A currency conversion is a well-formed line that cannot answer without
    # exchange rates, and the suite configures no app id — deliberately, since
    # a test that reaches the network is a test that fails when the network
    # does.
    defp tolerated?({:no_exchange_rate, _from, _to}), do: true

    # `sunrise` with no place named is answered where the reader is, which the
    # browser reports and a test suite has not got. The same shape as the
    # rates: the running application supplies the fact and this does not.
    defp tolerated?({:no_location, _event}), do: true

    # The sun really does not rise over Svalbard in December. That refusal is
    # what `08-the-sky` demonstrates on the line carrying it, so it is an
    # example working rather than an example broken.
    defp tolerated?({:no_event, _event}), do: true

    # Anything else is a broken line.
    defp tolerated?(_reason), do: false

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
      locales = Examples.all() |> Enum.map(&to_string(&1.locale)) |> Enum.uniq()

      assert length(locales) >= 3
      assert "en" in locales
    end
  end

  describe "the sample the page opens with" do
    # The one sheet rendered in whatever locale the reader arrives with. An
    # English sample under a German locale is not merely untranslated, it is
    # broken — `sum` totals nothing and `5 nights in Kyoto` answered `5
    # Zoll⋅Übernachtungen`, because `in` is inches and `Nächte` is a unit.
    test "answers every one of its lines, in every language it ships" do
      for locale <- [:en, :de, :fr, :es, :ja] do
        {source, tag} = Examples.sample(locale)

        dead =
          source
          |> Sheet.new(locale: tag)
          |> Map.fetch!(:lines)
          |> Enum.filter(&(&1.kind in [:expression, :aggregate, :trip, :trip_stop, :declaration]))
          |> Enum.reject(& &1.formatted)
          |> Enum.map(&"  #{&1.source} → #{inspect(&1.error)}")

        assert dead == [], "the #{locale} sample has dead lines:\n" <> Enum.join(dead, "\n")
      end
    end

    test "is written for the reader's language, not merely shown in it" do
      {german, tag} = Examples.sample(:de)

      assert to_string(tag) == "de"
      assert german =~ "summe"
      refute german =~ "sum\n"
    end

    test "and a language with no sample gets the English one, and is told so" do
      # Answering in English is fine; claiming the sheet is Portuguese while
      # showing English is not, so the locale comes back with the source.
      {source, tag} = Examples.sample("pt-BR")

      assert to_string(tag) == "en"
      assert source =~ "A first sheet"
    end

    test "a regional tag opens its language's sample and keeps its territory" do
      # `de-AT` types the same words as `de` and writes its dates differently,
      # so it gets the German sample read as Austrian. Returning `de` here cost
      # `en-AU` its kilometres.
      {source, tag} = Examples.sample("de-AT")

      assert to_string(tag) == "de-AT"
      assert source =~ "Ein erstes Blatt"

      {_source, australian} = Examples.sample("en-AU")

      assert to_string(australian) == "en-AU"
    end

    test "every sample round-trips through download and open" do
      for locale <- [:en, :de, :fr, :es, :ja] do
        {source, tag} = Examples.sample(locale)
        markdown = source |> Sheet.new(locale: tag) |> Sheet.to_markdown()

        assert {:ok, ^source, _locale} = Sheet.from_markdown(markdown)
      end
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
