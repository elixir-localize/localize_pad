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

  English and German. German is the proof that the thesis holds: everything
  *except* this table — month names, weekday names, unit names, currency
  symbols, number separators, date field order — comes from CLDR, so adding a
  locale is a page of operator words rather than a translation project.

  It is also where the limit shows. `nach` is both "in" (conversion) and
  "after" (relative date), and one word cannot carry both roles here; German
  keeps `nach` for "after" and uses `in` for conversion. Word *order* is the
  larger version of the same problem — `20 is 10% of what` has no word-for-word
  German form — and phrase rules per locale, rather than vocabulary per locale,
  are what that will eventually need.

  """

  @type role :: :to | :per | :after | :before | :of | :off | :on | :intersect

  @type deictic :: :now | :today | :tomorrow | :yesterday

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
      before: ["before", "ago", "until", "till"],

      # Percentage phrasing. "who can remember if it's times or divide" is
      # exactly the problem these solve, so they are core vocabulary rather
      # than a convenience.
      of: ["of"],
      off: ["off"],
      on: ["on"],

      # Set intersection over spans of time. "when are London and New York
      # both at work" is the question; `and` is how people write it.
      intersect: ["and", "∩", "overlap", "overlapping"]
    },
    de: %{
      # `1.234,5 Meter in Kilometer`. `nach` is deliberately absent: it is the
      # relative-date "after", and one word cannot be both.
      to: ["in", "zu", "als", "bis"],
      per: ["pro", "je"],
      after: ["nach"],
      before: ["vor"],
      # `20 % von 700`.
      of: ["von"],
      off: ["weniger"],
      on: ["plus"],
      intersect: ["und", "∩"]
    }
  }

  # Words naming a moment relative to the present. Kept separate from the role
  # table because these are *operands* rather than operators — `today` is a
  # date, not something that acts on one.
  #
  # CLDR does carry relative field names, but not reliably as bare input words
  # in every locale, so these are authored here alongside the operator
  # vocabulary and travel with it when a locale is added.
  @deictics %{
    en: %{
      now: ["now"],
      today: ["today"],
      tomorrow: ["tomorrow"],
      yesterday: ["yesterday"]
    },
    de: %{
      now: ["jetzt"],
      today: ["heute"],
      tomorrow: ["morgen"],
      yesterday: ["gestern"]
    }
  }

  @doc """
  Returns the moment a word names relative to the present, if any.

  ### Arguments

  * `word` - the surface form to look up.

  * `locale` - a locale identifier. Locales without an authored table fall
    back to `:en`.

  ### Returns

  * `{:ok, deictic}` where deictic is `:now`, `:today`, `:tomorrow` or
    `:yesterday`.

  * `:error` otherwise.

  ### Examples

      iex> LocalizePad.Lexicon.deictic("today", :en)
      {:ok, :today}

      iex> LocalizePad.Lexicon.deictic("Tuesday", :en)
      :error

  """
  @spec deictic(String.t(), atom()) :: {:ok, deictic()} | :error
  def deictic(word, locale \\ :en) when is_binary(word) do
    downcased = String.downcase(word)

    @deictics
    |> Map.get(locale, @deictics.en)
    |> Enum.find_value(:error, fn {moment, forms} ->
      if downcased in forms, do: {:ok, moment}
    end)
  end

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
      [:de, :en]

  """
  @spec known_locales() :: [atom()]
  def known_locales do
    @lexicons |> Map.keys() |> Enum.sort()
  end
end
