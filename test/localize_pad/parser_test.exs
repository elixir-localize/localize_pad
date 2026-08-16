defmodule LocalizePad.ParserTest do
  use ExUnit.Case, async: true

  alias LocalizePad.{Parser, Tokenizer}

  doctest LocalizePad.Parser

  defp parse(input, options \\ []) do
    {:ok, tokens} = Tokenizer.tokenize(input, locale: Keyword.get(options, :locale, :en))
    Parser.parse(tokens, variables: Keyword.get(options, :variables, []))
  end

  describe "precedence" do
    test "multiplication binds tighter than addition" do
      assert parse("2 + 3 * 4") ==
               {:ok, {:binary, :add, {:number, 2}, {:binary, :mul, {:number, 3}, {:number, 4}}}}
    end

    test "parentheses override precedence" do
      assert parse("(2 + 3) * 4") ==
               {:ok, {:binary, :mul, {:binary, :add, {:number, 2}, {:number, 3}}, {:number, 4}}}
    end

    test "exponentiation is right associative" do
      assert parse("2 ^ 3 ^ 2") ==
               {:ok, {:binary, :pow, {:number, 2}, {:binary, :pow, {:number, 3}, {:number, 2}}}}
    end

    test "juxtaposition binds tighter than explicit division, as in GNU units" do
      assert parse("kg m / s") ==
               {:ok,
                {:binary, :div, {:binary, :mul, {:unit, "kilogram"}, {:unit, "meter"}},
                 {:unit, "second"}}}
    end

    test "conversion binds loosest, so the whole expression converts" do
      assert parse("2 + 3 m to ft") ==
               {:ok,
                {:convert,
                 {:binary, :add, {:number, 2}, {:binary, :mul, {:number, 3}, {:unit, "meter"}}},
                 {:unit, "foot"}}}
    end
  end

  describe "operands" do
    test "a unit is an ordinary operand meaning one of that unit" do
      assert parse("meter") == {:ok, {:unit, "meter"}}
    end

    test "a quantity is a number multiplied by a unit" do
      assert parse("3 meters") == {:ok, {:binary, :mul, {:number, 3}, {:unit, "meter"}}}
    end

    test "unary minus" do
      assert parse("-5") == {:ok, {:number, -5}}
      assert parse("-(2 + 3)") == {:ok, {:neg, {:binary, :add, {:number, 2}, {:number, 3}}}}
    end

    test "a compound unit target parses as division" do
      assert parse("60 mph to km/h") ==
               {:ok,
                {:convert, {:binary, :mul, {:number, 60}, {:unit, "mile-per-hour"}},
                 {:binary, :div, {:unit, "kilometer"}, {:unit, "hour"}}}}
    end
  end

  describe "the two readings of 'in'" do
    test "reads as conversion when a target follows" do
      assert parse("3 m in ft") ==
               {:ok, {:convert, {:binary, :mul, {:number, 3}, {:unit, "meter"}}, {:unit, "foot"}}}
    end

    test "reads as inches when nothing follows" do
      assert parse("3 in") == {:ok, {:binary, :mul, {:number, 3}, {:unit, "inch"}}}
    end

    test "reads as inches mid-expression when no operand follows it" do
      assert parse("12 ft + 3 in") ==
               {:ok,
                {:binary, :add, {:binary, :mul, {:number, 12}, {:unit, "foot"}},
                 {:binary, :mul, {:number, 3}, {:unit, "inch"}}}}
    end
  end

  describe "prose tolerance" do
    test "words carrying no arithmetic meaning are discarded" do
      # The `$` is not noise — it makes each amount money. Everything between
      # the amounts is.
      assert {:ok, {:binary, :add, {:money, _breakfast}, {:money, _uber}}} =
               parse("$19 for breakfast + $22 for the uber")
    end

    test "the same line without currency markers is plain arithmetic" do
      assert parse("19 for breakfast + 22 for the uber") ==
               {:ok, {:binary, :add, {:number, 19}, {:number, 22}}}
    end

    test "a sentence containing an operator word is still just a sentence" do
      # "a" is a surface form of the :per role, as in "$24 a day". It must not
      # turn an ordinary sentence into a malformed expression.
      assert parse("just a thought") == {:error, :no_expression}
    end

    test "an empty line has no expression" do
      assert parse("") == {:error, :no_expression}
    end

    test "prose with no numbers at all has no expression" do
      assert parse("thinking about the weekend") == {:error, :no_expression}
    end
  end

  describe "variables" do
    test "a bound single-word name is a reference" do
      assert parse("cost * 2", variables: ["cost"]) ==
               {:ok, {:binary, :mul, {:variable, "cost"}, {:number, 2}}}
    end

    test "a bound phrase name is a reference" do
      assert parse("monthly rent / 4", variables: ["monthly rent"]) ==
               {:ok, {:binary, :div, {:variable, "monthly rent"}, {:number, 4}}}
    end

    test "the longest bound name wins" do
      assert parse("monthly rent / 4", variables: ["rent", "monthly rent"]) ==
               {:ok, {:binary, :div, {:variable, "monthly rent"}, {:number, 4}}}
    end

    test "an unbound name is discarded as prose, which can leave the rest malformed" do
      # Nothing distinguishes an undeclared variable from an ordinary word, so
      # "cost" is dropped like any other, leaving `* 2` — not an expression.
      # Either way the line shows no answer; the difference is only in the
      # error recorded against it.
      assert {:error, {:unexpected, "*"}} = parse("cost * 2")
    end
  end

  describe "malformed input" do
    test "an operator with nothing to its right is an error, not a crash" do
      assert {:error, _reason} = parse("2 +")
    end

    test "an unclosed parenthesis is reported" do
      assert parse("(2 + 3") == {:error, :unclosed_parenthesis}
    end
  end

  describe "prose does not join what it separates" do
    defp reads(source) do
      [line] = LocalizePad.Sheet.new(source, locale: :en).lines

      line.formatted || line.error
    end

    test "a number inside trailing prose is part of the prose" do
      # `19 + 22 for 2 coffees` was 82 — the trailing `2` juxtaposed onto the
      # sum. Implicit multiplication means two operands written next to each
      # other, and the words in between are the evidence that they were not.
      assert reads("19 + 22 for 2 coffees") == "41"
      assert reads("19 + 22 for breakfast") == "41"
    end

    test "but adjacent operands still multiply" do
      assert reads("3 meters") == "3 meters"
      assert reads("100 kg * 9.8 m/s^2") == "980 kilogram-meter-per-square-second"
    end

    test "a trailing quantity is meaning, not commentary" do
      # The line asked for something the sheet cannot give. Dropping `km` to
      # answer `19` would look like agreement.
      assert reads("19 + 22 for 2 km") == {:unexpected, "km"}
    end

    test "leftovers that never began as prose are still an error" do
      assert reads("2 (1 + 1)") == {:unexpected, "("}
    end
  end

  describe "the two readings of `in`" do
    test "prose after it means it is a preposition, not an inch" do
      # `12 items in the basket` answered `12 inches`.
      assert reads("12 items in the basket") == "12"
      assert reads("19 + 22 in cash") == "41"
    end

    test "it is still an inch where nothing follows" do
      assert reads("3 in") == "3 inches"
    end

    test "and a sum of inches is a sum, not a conversion" do
      # `3 in + 2 in` was refused: the `+` counted as an operand following the
      # first `in`, so the line read as converting three of nothing into two
      # inches. Nothing is ever converted *to* a signed number.
      assert reads("3 in + 2 in") == "5 inches"
    end

    test "a real conversion is untouched" do
      assert reads("100 celsius in fahrenheit") == "212 degrees Fahrenheit"
      assert reads("3 meters to feet") == "9.84252 feet"
    end
  end
end
