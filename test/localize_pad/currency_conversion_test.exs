defmodule LocalizePad.CurrencyConversionTest do
  use ExUnit.Case, async: true

  alias LocalizePad.{Currency, Sheet}

  defp answer(source, locale) do
    [line] = Sheet.new(source, locale: locale).lines

    line.formatted || line.error
  end

  describe "naming the currency to convert to" do
    # No rates are configured in the suite, so a resolved target reports that it
    # has no rate. That is the assertion: `{:no_exchange_rate, :EUR, :AUD}` says
    # the *target* was understood, where an unresolved one would leave the line
    # as prose and hand back the original amount.
    test "an ISO code" do
      assert answer("200 EUR in AUD", "en") == {:no_exchange_rate, :EUR, :AUD}
    end

    test "the name CLDR gives it, singular or plural" do
      assert answer("200 EUR in Australian dollar", "en") == {:no_exchange_rate, :EUR, :AUD}
      assert answer("200 EUR in Australian dollars", "en") == {:no_exchange_rate, :EUR, :AUD}
    end

    test "and that name in the reader's own language" do
      assert answer("200 EUR in australische Dollar", "de") == {:no_exchange_rate, :EUR, :AUD}
    end

    test "the reader's own currency, without naming it" do
      # The territory decides which, exactly as it decides whether a distance
      # is miles.
      assert answer("200 EUR in preferred currency", "en-AU") == {:no_exchange_rate, :EUR, :AUD}
      assert answer("200 EUR in local currency", "en-AU") == {:no_exchange_rate, :EUR, :AUD}
    end

    test "which is a no-op when the reader already uses it" do
      assert answer("200 EUR in preferred currency", "de") == "200,00 €"
    end
  end

  describe "currency names are ordinary words too" do
    test "so they only count where the answer belongs" do
      # `dollar`, `pound`, `real` and `won` are words people write. Claiming
      # them anywhere would turn prose into money.
      assert answer("19 + 22 for the dollar menu", "en") == "41"
      assert answer("200 EUR for australian dollars", "en") == "€200.00"
    end

    test "and an unrecognised target leaves the line as prose" do
      # `200 EUR in breakfast` is two hundred euros *on* breakfast, which is
      # the same reading that makes `19 + 22 in cash` forty-one.
      assert answer("200 EUR in breakfast", "en") == "€200.00"
    end
  end

  describe "the name index is CLDR's, not ours" do
    test "every locale names every currency" do
      assert Currency.resolve_name("australian dollar", :en) == {:ok, :AUD}
      assert Currency.resolve_name("australischer dollar", :de) == {:ok, :AUD}
      assert Currency.resolve_name("yen japonais", :fr) == {:ok, :JPY}
      assert Currency.resolve_name("euro", :es) == {:ok, :EUR}
    end

    test "and a word that names none is refused" do
      assert Currency.resolve_name("breakfast", :en) == :error
    end
  end
end
