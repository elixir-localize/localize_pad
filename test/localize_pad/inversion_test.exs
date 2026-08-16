defmodule LocalizePad.InversionTest do
  use ExUnit.Case, async: true

  alias LocalizePad.{Inversion, Sheet}

  doctest LocalizePad.Inversion

  defp answer(source, locale \\ :en) do
    [line] = Sheet.new(source, locale: locale).lines

    line.formatted || line.error
  end

  describe "the three percentage comparisons" do
    # The same two numbers, three answers. Getting these confused is the exact
    # thing the phrasing exists to prevent, so each is pinned separately.
    test "of, off and more than are different questions" do
      assert answer("180 is what % of 200") == "90%"
      assert answer("180 is what % off 200") == "10%"
      assert answer("220 is what % more than 200") == "10%"
    end

    test "less than reads as the fall, like off" do
      assert answer("180 is what % less than 200") == "10%"
    end

    test "money asks the same question and gets a plain percentage" do
      # A ratio of two amounts is a number, not an amount.
      assert answer("$180 is what % off $200") == "10%"
    end

    test "a whole of zero has no answer, and says so" do
      assert answer("180 is what % off 0") == :indeterminate
    end
  end

  describe "solving for the whole" do
    test "a part and its share give the whole" do
      assert answer("20 is 10% of what") == "200"
      assert answer("50 is 25% of what") == "200"
    end

    test "money keeps its currency" do
      assert answer("$20 is 10% of what") == "$200.00"
    end

    test "a share of zero has no answer" do
      assert answer("20 is 0% of what") == :indeterminate
    end

    test "the hole's position is what distinguishes this from the comparison" do
      # `20 is 10% of what` asks for the whole. `180 is what % of 200` asks for
      # the share. Same preposition, and only the position of `what` separates
      # them.
      assert answer("20 is 10% of what") == "200"
      assert answer("180 is what % of 200") == "90%"
    end
  end

  describe "restating a rate" do
    test "per day becomes per year on the Gregorian mean" do
      assert answer("$30/day is what per year") == "$10,957.28/year"
      assert answer("$30 per day is what per year") == "$10,957.28/year"
    end

    test "and any other period" do
      assert answer("$99/week is what per month") == "$430.46/month"
    end
  end

  describe "proportions" do
    test "the fourth term" do
      assert answer("6 is to 60 as 8 is to what") == "80"
    end

    test "a first term of zero has no answer" do
      assert answer("0 is to 60 as 8 is to what") == :indeterminate
    end
  end

  describe "what is not a question" do
    test "a line with no hole is untouched" do
      assert answer("19 + 22") == "41"
      assert answer("30% of 700") == "210"
      assert answer("200 + 10%") == "220"
    end

    test "a hole with nothing to solve for is refused, not guessed" do
      # `what` alone does not make a question this can answer. Inventing a
      # reading here would produce a confident wrong number.
      assert answer("what is this") == :no_expression
      assert answer("what") == :no_expression
    end

    test "prose containing the word survives as prose" do
      assert answer("19 + 22 for whatever") == "41"
    end
  end

  describe "matching" do
    test "reports which question was asked" do
      for {source, expected} <- [
            {"180 is what % of 200", :percent_of},
            {"180 is what % off 200", :percent_off},
            {"220 is what % more than 200", :percent_more},
            {"20 is 10% of what", :whole},
            {"6 is to 60 as 8 is to what", :proportion},
            {"$30/day is what per year", :rate}
          ] do
        {:ok, tokens} = LocalizePad.Tokenizer.tokenize(source, locale: :en)

        assert {:ok, {:inversion, ^expected, _slots}} = Inversion.match(tokens, locale: :en),
               "#{source} did not match as #{expected}"
      end
    end

    test "a line without the hole never reaches here" do
      {:ok, tokens} = LocalizePad.Tokenizer.tokenize("19 + 22", locale: :en)

      assert Inversion.match(tokens, locale: :en) == :error
    end
  end
end
