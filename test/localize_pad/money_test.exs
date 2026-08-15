defmodule LocalizePad.MoneyTest do
  use ExUnit.Case, async: true

  alias LocalizePad.Sheet

  doctest LocalizePad.Currency
  doctest LocalizePad.Percentage

  defp answer(source, options \\ []) do
    [line] = Sheet.new(source, Keyword.put_new(options, :locale, :en)).lines
    line.formatted || line.error
  end

  defp shown(source, options \\ []) do
    [line] = Sheet.new(source, Keyword.put_new(options, :locale, :en)).lines
    line.formatted
  end

  # Every row of the table in `LocalizePad.Percentage`. This is the feature
  # people praise a notepad calculator for, and the rules only look arbitrary
  # until they are all written down together.
  describe "the percentage truth table" do
    test "a percentage applied to a number is relative to that number" do
      assert answer("200 + 10%") == "220"
      assert answer("200 - 10%") == "180"
    end

    test "two percentages combine as percentages" do
      assert answer("10% + 20%") == "30%"
      assert answer("90% - 40%") == "50%"
    end

    test "a bare number beside a percentage is read as a proportion" do
      # 0.4 is 40%, so this is 70% rather than 30.4%.
      assert answer("30% + 0.4") == "70%"
    end

    test "multiplication always yields a plain number, whichever side" do
      assert answer("50% * 30") == "15"
      assert answer("30 * 50%") == "15"
    end

    test "the of, off and on phrases" do
      assert answer("10% of 200") == "20"
      assert answer("10% off 200") == "180"
      assert answer("10% on 200") == "220"
    end

    test "a percentage on its own is a percentage" do
      assert answer("20%") == "20%"
      assert answer("20 percent") == "20%"
    end

    test "percentages apply to quantities too, keeping the unit" do
      assert answer("100 kg + 15%") == "115 kilograms"
    end

    test "percentages are written the way the locale writes them" do
      # German puts a *non-breaking* space before the sign — asserting the
      # literal codepoint keeps a later tidy-up from replacing it with an
      # ordinary space.
      assert answer("10% + 20%", locale: :en) == "30%"
      assert answer("10% + 20%", locale: :de) == "30\u00A0%"
    end
  end

  describe "recognising money" do
    test "a symbol binds to the amount that follows it" do
      assert answer("$19") == "$19.00"
      assert answer("€30") == "€30.00"
    end

    test "an ISO code binds to the amount before it" do
      assert answer("19 USD") == "$19.00"
      assert answer("100 GBP") == "£100.00"
    end

    test "a bare number is never money" do
      # `Money.parse/2` would read "19" as 19 US dollars. Doing that here would
      # turn every number in every sheet into money.
      assert answer("19") == "19"
    end

    test "a lowercase word that happens to be an ISO code stays a unit" do
      # CUP is the Cuban peso. `cup` is a unit of volume, and far more likely
      # to be what someone means.
      assert answer("2 cup to mL") == "473.176473 milliliters"
    end

    test "the dollar sign follows the reader's locale" do
      assert LocalizePad.Currency.resolve("$", :en) == {:ok, :USD}
      assert LocalizePad.Currency.resolve("$", :"en-AU") == {:ok, :AUD}
      assert LocalizePad.Currency.resolve("$", :de) == {:ok, :EUR}
    end
  end

  describe "money arithmetic" do
    test "the classic mixed line, now with currency" do
      assert answer("$19 for breakfast + $22 for the uber") == "$41.00"
    end

    test "multiplication and division by a number" do
      assert answer("€30 * 3") == "€90.00"
      assert answer("$100 / 4") == "$25.00"
    end

    test "money over money is a ratio, not money" do
      assert answer("$50 / $200") == "0.25"
    end

    test "a percentage of money keeps the currency and its rounding" do
      assert answer("$300 + 15%") == "$345.00"
      assert answer("$300 - 10%") == "$270.00"
    end

    test "money is written the way the locale writes it" do
      assert answer("€30", locale: :de) == "30,00\u00A0€"
    end
  end

  describe "currency conversion" do
    test "reports the missing rate rather than inventing a number" do
      # Conversion needs an Open Exchange Rates app id. Without one there are
      # no rates, and a made-up answer would be worse than none.
      assert {:no_exchange_rate, :USD, :EUR} = answer("10 USD in EUR")
      assert shown("10 USD in EUR") == nil
    end
  end

  describe "rates" do
    test "money over a unit is a rate" do
      assert answer("$99 per week") == "$99.00/week"
      assert answer("$99 / week") == "$99.00/week"
      assert answer("$24 a day") == "$24.00/day"
    end

    test "a quantity over a unit needs no rate type at all" do
      # `Localize.Unit` already models this as a compound unit.
      assert answer("90 km / 3 day") == "30 kilometers per day"
    end

    test "a rate multiplied by a quantity gives an amount" do
      assert answer("$50/week * 12 weeks") == "$600.00"
    end

    test "converting the denominator uses the Gregorian mean month" do
      # Localize declines `day -> month` because a month has no fixed length,
      # and it is right to. A notepad still has to answer the question, so
      # `LocalizePad.Rate` supplies the convention: 365.2425 days a year,
      # one twelfth of that a month.
      assert answer("$30/day in month") == "$913.11/month"
      assert answer("€30/day in €/month") == "€913.11/month"
    end

    test "the convention agrees with the conversions Localize does allow" do
      # 7 days to the week is exact either way, so using the table uniformly
      # introduces no disagreement.
      assert answer("$10/day in week") == "$70.00/week"
      assert answer("$24/day in hour") == "$1.00/hour"
    end

    test "rates add, in the left operand's denominator" do
      assert answer("$20/day + $300/week") == "$62.86/day"
    end

    test "the denominator is named in the singular, in the sheet's locale" do
      assert answer("$99 per week", locale: :en) == "$99.00/week"
      assert answer("99 EUR per week", locale: :de) == "99,00\u00A0€/Woche"
    end
  end

  describe "totals" do
    test "money sums with money" do
      sheet = Sheet.new("$19\n$22", locale: :en)

      assert Sheet.total(sheet) == Money.new(:USD, 41)
    end
  end
end
