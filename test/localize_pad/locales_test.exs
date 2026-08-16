defmodule LocalizePad.LocalesTest do
  use ExUnit.Case, async: true

  alias LocalizePad.{Locales, Sheet}

  doctest LocalizePad.Locales

  defp answer(source, locale) do
    [line] = Sheet.new(source, locale: locale).lines

    line.formatted || line.error
  end

  describe "resolving a tag" do
    defp resolved(locale) do
      {:ok, language_tag} = Locales.resolve(locale)

      language_tag
    end

    test "the territory survives" do
      # The whole point. `cldr_locale_id` would collapse this to `en` and take
      # every territory-dependent answer with it.
      assert %{language: :en, territory: :AU} = resolved("en-AU")
      assert %{language: :en, territory: :GB} = resolved("en-GB")
    end

    test "a language tag is what a sheet carries, not a name for one" do
      # Resolved once at the boundary, so nothing downstream has to ask CLDR
      # again to find out which English it is holding.
      assert %Localize.LanguageTag{} = resolved("en-AU")
      assert to_string(resolved("en-AU")) == "en-AU"
    end

    test "an already-resolved tag resolves to itself" do
      tag = resolved("en-AU")

      assert resolved(tag) == tag
    end

    test "a plain language is still a locale" do
      assert to_string(resolved("en")) == "en"
      assert to_string(resolved(:ja)) == "ja"
    end

    test "surrounding space is not a different locale" do
      assert to_string(resolved("  en-AU  ")) == "en-AU"
    end

    test "a language with no data is refused, not substituted" do
      # `Localize.validate_locale/1` accepts both of these and then reads them
      # with the default locale's rules, which answers `1.234,5` as though it
      # were English. Refusing is the only honest option.
      assert Locales.resolve("it") == {:error, {:unsupported, "it"}}
      assert Locales.resolve("pt-BR") == {:error, {:unsupported, "pt"}}
    end

    test "nonsense is refused as nonsense" do
      assert Locales.resolve("not a locale") == {:error, :unknown}
      assert Locales.resolve(nil) == {:error, :unknown}
      assert Locales.resolve(123) == {:error, :unknown}
    end

    test "a blank locale is refused rather than defaulted" do
      # `Localize.validate_locale/1` accepts these and returns a tag carrying
      # the default language, so without this they would answer in English.
      # The combobox emits one on every keystroke that clears the field.
      assert Locales.resolve("") == {:error, :unknown}
      assert Locales.resolve("   ") == {:error, :unknown}
      assert Locales.resolve(:"") == {:error, :unknown}
    end
  end

  describe "suggestions" do
    test "offer only locales whose data was downloaded" do
      tags = Locales.suggestions() |> Enum.map(&elem(&1, 1))

      assert "en-AU" in tags
      assert "en-GB" in tags
      refute "it" in tags
    end

    test "every suggestion resolves" do
      for {_name, tag} <- Locales.suggestions() do
        assert {:ok, language_tag} = Locales.resolve(tag),
               "#{tag} is offered but does not resolve"

        assert to_string(language_tag) == tag
      end
    end

    test "each is named in its own language" do
      names = Locales.suggestions() |> Enum.map(&elem(&1, 0))

      assert "Australian English" in names
      assert "Deutsch" in names
    end

    test "no two suggestions read the same" do
      # A list with two rows both saying "English" tells the reader nothing
      # about which one they are choosing.
      names = Locales.suggestions() |> Enum.map(&elem(&1, 0))

      assert names == Enum.uniq(names)
    end
  end

  describe "the territory changes the answer" do
    test "a slashed date is read in the order the territory writes it" do
      # The question behind all of this: which English? 3/4/2026 is two
      # different days depending on who wrote it.
      assert answer("3/4/2026", "en-US") == "March 4, 2026"
      assert answer("3/4/2026", "en-AU") == "3 April 2026"
      assert answer("3/4/2026", "en-GB") == "3 April 2026"
    end

    test "and the plain language is not a stand-in for either" do
      # `en` is US convention, so an Australian sheet tagged `en` is wrong in a
      # way nothing on screen reveals.
      refute answer("3/4/2026", "en") == answer("3/4/2026", "en-AU")
    end
  end
end
