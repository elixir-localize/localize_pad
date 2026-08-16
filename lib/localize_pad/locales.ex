defmodule LocalizePad.Locales do
  @moduledoc """
  Which locales this sheet can honestly be read in, and what they are called.

  ## Why a language tag and not a language

  "English" is not a locale. `42.195 km` is a distance an Australian leaves in
  kilometres and an American converts to miles; `1,234.5` and `1.234,5` are the
  same number written for different readers. Both answers come from the
  *territory* subtag, so the sheet keeps the whole tag — `en-AU`, not `en`.

  This is also why the picker is a combobox over a fixed list. The useful set
  of tags is not enumerable: somebody will want `en-IE` or `es-CO`, and a menu
  of five languages cannot express either.

  ## Why not simply accept anything valid

  `Localize.validate_locale/1` accepts `it` and `pt-BR` whether or not their
  CLDR data was ever downloaded, and without that data they fall back to the
  default locale — so `1.234,5` in Italian would be read with English rules and
  answered confidently and wrongly.

  So a tag is accepted here only when its *language* has data. Territory
  variants inherit it, which is what makes `en-AU` and `de-AT` work while
  `it` is refused rather than silently answered in English.

  """

  @typedoc """
  A resolved locale, as this application carries one.

  Always the full language tag. Strings and atoms are accepted wherever a
  locale goes *in* — `locale: :en` reads better in a test than the struct
  would — but they are resolved at the boundary and never stored, because a
  bare `:de` cannot say which German and a bare `"en"` cannot say which
  English.
  """
  @type tag :: Localize.LanguageTag.t()

  @typedoc """
  Anything acceptable *as* a locale on the way in.

  Distinct from `t:tag/0`, which is what a resolved locale is. Functions that
  take a locale accept all three; functions that store or return one deal in
  tags only.
  """
  @type locale :: tag() | String.t() | atom()

  @doc """
  The locale tags offered as suggestions, each with its display name.

  These are exactly the configured `:supported_locales`, because those are the
  ones whose conventions have been checked. Anything else the reader types
  still resolves — through CLDR's own inheritance, which is usually right:
  `en-IE` inherits `en-GB` rather than `en`, so its dates come back in the
  order Ireland writes them.

  ### Returns

  * A list of `{name, tag}` tuples, the name written in that locale's own
    language.

  ### Examples

      iex> {name, tag} = hd(LocalizePad.Locales.suggestions())
      iex> is_binary(name) and is_binary(tag)
      true

  """
  @spec suggestions() :: [{String.t(), String.t()}]
  def suggestions do
    for locale <- Localize.supported_locales(),
        tag = to_string(locale),
        {:ok, name} <- [display_name(tag)] do
      {name, tag}
    end
  end

  @doc """
  Resolves a locale to the language tag the sheet should carry.

  The whole `t:Localize.LanguageTag.t/0` rather than a string, because it is
  the only form that answers every question downstream asks without asking
  CLDR again: the language keys the operator lexicon, the territory decides
  date order and unit preference, and `cldr_locale_id` names the data file.
  Reduce it to a string and each call site has to re-derive the rest, which is
  where `en-AU` quietly became `en`.

  ### Arguments

  * `locale` - a BCP 47 language tag as typed, an atom, or an already-resolved
    `t:Localize.LanguageTag.t/0`.

  ### Returns

  * `{:ok, language_tag}` when the locale is valid and its language has data.

  * `{:error, :unknown}` when it is not a language tag at all.

  * `{:error, {:unsupported, language}}` when it parses but its language has
    no data, and reading a sheet in it would silently fall back to another
    language's rules.

  ### Examples

      iex> {:ok, tag} = LocalizePad.Locales.resolve("en-AU")
      iex> {to_string(tag), tag.territory}
      {"en-AU", :AU}

      iex> LocalizePad.Locales.resolve("it")
      {:error, {:unsupported, "it"}}

      iex> LocalizePad.Locales.resolve("not a locale")
      {:error, :unknown}

  """
  @spec resolve(tag() | String.t() | atom()) ::
          {:ok, tag()} | {:error, :unknown | {:unsupported, String.t()}}
  def resolve(locale) when is_binary(locale) or is_atom(locale) or is_struct(locale) do
    locale = if is_binary(locale), do: String.trim(locale), else: locale

    case validate(locale) do
      {:ok, language_tag} ->
        # The *language* subtag, not `cldr_locale_id`. The latter is the data
        # file CLDR resolved to, and for a language never downloaded it is the
        # default — `it` resolves to `:en`, so testing it would accept Italian
        # and then read the sheet in English.
        if language_tag.language in Localize.supported_locales() do
          {:ok, language_tag}
        else
          {:error, {:unsupported, to_string(language_tag.language)}}
        end

      {:error, _reason} ->
        {:error, :unknown}
    end
  end

  def resolve(_locale), do: {:error, :unknown}

  # An empty locale is not a locale, and `Localize.validate_locale/1` does not
  # treat it as one to reject — it hands back a tag whose language is the
  # default, so `""` would resolve to English and be answered rather than
  # refused. The combobox produces exactly this on every clearing keystroke.
  defp validate(""), do: {:error, :blank}
  defp validate(nil), do: {:error, :blank}
  defp validate(:""), do: {:error, :blank}
  defp validate(locale), do: Localize.validate_locale(locale)

  defp display_name(tag) do
    case Localize.Language.display_name(tag, locale: tag) do
      {:ok, name} -> {:ok, capitalize(name)}
      {:error, _reason} -> :error
    end
  end

  # Several languages name themselves in lower case — "français", "español" —
  # and CLDR is right to. In a list of proper nouns beside "Deutsch" they read
  # as a mistake, so the first letter is raised and the rest left alone.
  defp capitalize(<<first::utf8, rest::binary>>), do: String.upcase(<<first::utf8>>) <> rest
  defp capitalize(name), do: name
end
