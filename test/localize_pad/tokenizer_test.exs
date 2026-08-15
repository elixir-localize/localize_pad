defmodule LocalizePad.TokenizerTest do
  use ExUnit.Case, async: true

  alias LocalizePad.{Token, Tokenizer}

  doctest LocalizePad.Token
  doctest LocalizePad.Lexicon
  doctest LocalizePad.Tokenizer

  defp kinds(input, locale \\ :en) do
    {:ok, tokens} = Tokenizer.tokenize(input, locale: locale)
    Enum.map(tokens, &{&1.kind, &1.value})
  end

  describe "numbers" do
    test "reads a bare integer" do
      assert kinds("42") == [number: 42]
    end

    test "reads a float" do
      assert kinds("9.8") == [number: 9.8]
    end

    test "reads grouping separators using the locale's own symbols" do
      assert kinds("1,234.5") == [number: 1234.5]
    end

    test "the same digits read differently in a locale that swaps the separators" do
      assert kinds("1.234,5", :de) == [number: 1234.5]
      assert kinds("1.234,5", :en) == [{:number, 1.234}, {:operator, :comma}, {:number, 5}]
    end

    test "reads underscore digit separators" do
      assert kinds("1_000_000") == [number: 1_000_000]
    end
  end

  describe "units" do
    test "resolves a plural unit name to its CLDR identifier" do
      assert kinds("3 meters") == [number: 3, unit: "meter"]
    end

    test "resolves abbreviations" do
      assert kinds("3 kg") == [number: 3, unit: "kilogram"]
      assert kinds("60 mph") == [number: 60, unit: "mile-per-hour"]
    end

    test "compound units arrive as unit-operator-unit for the parser to assemble" do
      assert kinds("9.8 m/s") == [number: 9.8, unit: "meter", operator: :divide, unit: "second"]
    end
  end

  describe "operators" do
    test "reads arithmetic operators" do
      assert kinds("2 + 2") == [number: 2, operator: :plus, number: 2]
      assert kinds("2 * 2") == [number: 2, operator: :times, number: 2]
      assert kinds("2 ^ 2") == [number: 2, operator: :power, number: 2]
    end

    test "reads the typographic multiplication and division signs" do
      assert kinds("2 × 2") == [number: 2, operator: :times, number: 2]
      assert kinds("2 ÷ 2") == [number: 2, operator: :divide, number: 2]
    end

    test "reads a multi-character operator without splitting its prefix" do
      assert kinds("2 ** 3") == [number: 2, operator: :power, number: 3]
    end

    test "reads parentheses and assignment" do
      assert kinds("(1)") == [operator: :lparen, number: 1, operator: :rparen]
      assert kinds("cost = 5") == [word: "cost", operator: :assign, number: 5]
    end
  end

  describe "keywords" do
    test "reads the conversion keyword in each of its spellings" do
      assert kinds("3 m to ft") == [number: 3, unit: "meter", keyword: :to, unit: "foot"]
      assert kinds("3 m as ft") == [number: 3, unit: "meter", keyword: :to, unit: "foot"]
      assert kinds("3 m -> ft") == [number: 3, unit: "meter", keyword: :to, unit: "foot"]
    end

    test "reads the division keyword" do
      assert kinds("99 per week") == [number: 99, keyword: :per, unit: "week"]
    end
  end

  describe "ambiguity" do
    test "'in' reports both the conversion keyword and the inch unit" do
      {:ok, [_number, token]} = Tokenizer.tokenize("3 in", locale: :en)

      assert token.kind == :keyword
      assert token.value == :to
      assert Token.as(token, :unit) == {:ok, "inch"}
      assert Token.is?(token, :unit)
    end

    test "an unambiguous keyword carries no unit reading" do
      {:ok, [_number, _unit, token, _target]} = Tokenizer.tokenize("3 m to ft", locale: :en)

      assert Token.as(token, :unit) == :error
    end
  end

  describe "prose tolerance" do
    test "words with no arithmetic meaning survive as :word rather than failing" do
      assert kinds("19 for breakfast + 22 for the uber") == [
               {:number, 19},
               {:word, "for"},
               {:word, "breakfast"},
               {:operator, :plus},
               {:number, 22},
               {:word, "for"},
               {:word, "the"},
               {:word, "uber"}
             ]
    end

    test "a currency marker binds to its amount and the prose still falls away" do
      assert [
               {:money, _breakfast},
               {:word, "for"},
               {:word, "breakfast"},
               {:operator, :plus},
               {:money, _uber},
               {:word, "for"},
               {:word, "the"},
               {:word, "uber"}
             ] = kinds("$19 for breakfast + $22 for the uber")
    end

    test "an empty line tokenizes to nothing" do
      assert kinds("") == []
    end

    test "a line of pure prose tokenizes without error" do
      assert {:ok, _tokens} = Tokenizer.tokenize("just some thoughts here", locale: :en)
    end

    test "an unknown locale does not raise" do
      assert {:ok, _tokens} = Tokenizer.tokenize("2 + 2", locale: :"zz-nonsense")
    end
  end
end
