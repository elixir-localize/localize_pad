defmodule LocalizePad.Lexicon do
  @moduledoc """
  The operator vocabulary of the calculation language, per locale.

  A lexicon maps *roles* — what a word does — to the surface forms that express
  it. `:to` is the conversion role; `to`, `in` and `as` all express it in
  English.

  ## Why this is hand-authored and not derived

  Almost everything else this app needs is CLDR data reached through Localize:
  month and weekday names, era markers, unit display names and their plurals,
  currency names and symbols, timezone city names, and the decimal and grouping
  separators that decide how a number reads. None of that appears here.

  What CLDR does not supply is the vocabulary of *operators* a person types
  when writing a calculation in prose — `of`, `off`, `per`, `each`, `after`,
  `ago`. Those are the entries in this file, and they are the reason a locale
  can be added for roughly a hundred lines of data rather than thousands.

  ## Why not Gettext

  These are input alternatives, not output messages: many surface forms map to
  one role, which is the opposite of a msgid mapping to one rendering. A plain
  data table is the right vehicle. Translatable *output* still goes through
  `LocalizePadWeb.Gettext` and MF2.

  ## Scope

  English only for now. The roles here are the ones M1 can act on; percentage,
  date and finance roles arrive with the milestones that evaluate them.

  """

  @type role :: :to | :per | :after | :before

  @lexicons %{
    en: %{
      # Conversion. "in" is also the unit `inch`; the tokenizer reports both
      # readings and the parser picks by position.
      to: ["to", "in", "as", "->"],

      # Division in prose. "$99 per week", "3 hours a day".
      per: ["per", "a", "each"],

      # Relative dates. "3 weeks after March 14" puts the duration first and
      # the date second, which is the reverse of "March 14 + 3 weeks" — the
      # evaluator swaps the operands rather than the parser, so the two
      # phrasings share one code path.
      after: ["after", "from"],
      before: ["before", "ago", "until", "till"]
    }
  }

  @doc """
  Returns the role a word plays in the given locale, if any.

  Lookup is case-insensitive.

  ### Arguments

  * `word` - the surface form to look up.

  * `locale` - a locale identifier. Only locales with an authored lexicon
    resolve; others fall back to `:en`.

  ### Returns

  * `{:ok, role}` when the word is in the locale's lexicon.

  * `:error` otherwise.

  ### Examples

      iex> LocalizePad.Lexicon.role("to", :en)
      {:ok, :to}

      iex> LocalizePad.Lexicon.role("PER", :en)
      {:ok, :per}

      iex> LocalizePad.Lexicon.role("meters", :en)
      :error

  """
  @spec role(String.t(), atom()) :: {:ok, role()} | :error
  def role(word, locale \\ :en) when is_binary(word) do
    downcased = String.downcase(word)

    locale
    |> lexicon()
    |> Enum.find_value(:error, fn {role, forms} ->
      if downcased in forms, do: {:ok, role}
    end)
  end

  @doc """
  Returns the whole lexicon table for a locale.

  ### Arguments

  * `locale` - a locale identifier.

  ### Returns

  * A map of role to surface forms. Locales without an authored lexicon return
    the `:en` table, so the app degrades to English operator words rather than
    losing the ability to calculate.

  ### Examples

      iex> LocalizePad.Lexicon.lexicon(:en) |> Map.fetch!(:to)
      ["to", "in", "as", "->"]

  """
  @spec lexicon(atom()) :: %{role() => [String.t()]}
  def lexicon(locale \\ :en) do
    Map.get(@lexicons, locale, @lexicons.en)
  end

  @doc """
  Returns the locales that have an authored lexicon.

  ### Returns

  * A list of locale identifiers.

  ### Examples

      iex> LocalizePad.Lexicon.known_locales()
      [:en]

  """
  @spec known_locales() :: [atom()]
  def known_locales do
    Map.keys(@lexicons)
  end
end
