defmodule LocalizePad.EvaluatorTest do
  use ExUnit.Case, async: true

  alias LocalizePad.{Evaluator, Parser, Tokenizer}

  doctest LocalizePad.Evaluator

  defp eval(input, environment \\ %{}) do
    {:ok, tokens} = Tokenizer.tokenize(input, locale: :en)

    with {:ok, ast} <- Parser.parse(tokens, variables: Map.keys(environment)) do
      Evaluator.eval(ast, environment)
    end
  end

  defp value(input, environment \\ %{}) do
    {:ok, result} = eval(input, environment)
    result
  end

  describe "numbers" do
    test "arithmetic" do
      assert value("2 + 3") == 5
      assert value("10 - 3") == 7
      assert value("6 * 7") == 42
      assert value("10 / 4") == 2.5
    end

    test "integer exponentiation stays exact" do
      assert value("2 ^ 10") == 1024
    end

    test "precedence is honoured through to the answer" do
      assert value("2 + 3 * 4") == 14
      assert value("(2 + 3) * 4") == 20
    end

    test "division by zero is an error, not a crash" do
      assert eval("1 / 0") == {:error, :division_by_zero}
    end
  end

  describe "quantities" do
    test "a number times a unit is a quantity" do
      quantity = value("3 meters")

      assert quantity.name == "meter"
      assert quantity.value == 3
    end

    test "conversion" do
      assert value("3 meters to feet").name == "foot"

      # Float conversion lands on 211.99999999999997. The value carries the
      # full precision and the formatter is what rounds for display — hence the
      # delta here rather than an exact comparison.
      assert_in_delta value("100 celsius to fahrenheit").value, 212, 0.000001
    end

    test "addition converts the right operand into the left's unit" do
      sum = value("12 ft + 3 in")

      assert sum.name == "foot"
      assert sum.value == 12.25
    end

    test "multiplication builds a compound unit" do
      assert value("100 kg * 9.8 m/s^2").name == "kilogram-meter-per-square-second"
    end

    test "division builds a rate" do
      rate = value("100 miles / 2 hours")

      assert rate.name == "mile-per-hour"
      assert rate.value == 50
    end

    test "a compound conversion target works" do
      assert value("60 mph to km/h").name == "kilometer-per-hour"
    end

    test "a bare unit means one of it" do
      assert value("meter").value == 1
    end
  end

  describe "declining rather than guessing" do
    test "adding non-conformable quantities is an error" do
      assert {:error, %Localize.UnitConversionError{}} = eval("3 meters + 2 seconds")
    end

    test "adding a bare number to a quantity is an error" do
      assert {:error, {:incompatible, "meter", :number}} = eval("3 meters + 2")
      assert {:error, {:incompatible, :number, "meter"}} = eval("2 + 3 meters")
    end

    test "an unknown unit is reported rather than raised" do
      assert {:error, _reason} = eval("3 zorkmids to feet")
    end
  end

  describe "variables" do
    test "a bound variable resolves" do
      assert value("cost * 2", %{"cost" => 550}) == 1100
    end

    test "a phrase-named variable resolves" do
      assert value("monthly rent / 4", %{"monthly rent" => 2000}) == 500.0
    end

    test "a quantity-valued variable participates in unit arithmetic" do
      {:ok, distance} = Localize.Unit.new(42.195, "kilometer")

      assert value("distance to miles", %{"distance" => distance}).name == "mile"
    end
  end

  describe "prose" do
    test "the classic mixed line" do
      assert value("$19 for breakfast + $22 for the uber") == 41
    end
  end
end
