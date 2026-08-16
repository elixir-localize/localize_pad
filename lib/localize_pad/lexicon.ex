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

  English, German, French, Spanish and Japanese. German is the proof that the thesis holds: everything
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
    },
    fr: %{
      to: ["en", "vers"],
      per: ["par"],
      after: ["après"],
      before: ["avant"],
      # `20 % de 700`. `de` is one of the commonest words in French, so it
      # claims more lines here than `of` does in English — the cost of a
      # vocabulary-only lexicon.
      of: ["de"],
      intersect: ["et", "∩"]
    },
    es: %{
      to: ["en", "a"],
      per: ["por"],
      after: ["después"],
      before: ["antes"],
      of: ["de"],
      intersect: ["y", "∩"]
    },
    ja: %{
      # Japanese marks its arguments with postpositional particles rather than
      # with infix words. `100キロメートルをマイルで` reads "100 kilometres, as
      # miles" — and `を` happens to sit *between* the two operands, so an
      # infix parser can use it. That is luck rather than design: see the note
      # on limits above.
      to: ["を", "は", "→"],
      per: ["あたり", "ごと"],
      after: ["後"],
      before: ["前"],
      of: ["の"],
      intersect: ["と", "∩"]
    }
  }

  # Recurrence vocabulary. Weekday and month names are *not* here — CLDR
  # supplies those, so `every Monday` and `jeden Montag` find their day the
  # same way. What is left is the three things CLDR has no table for: the word
  # that marks a phrase as recurring, the spelled ordinals that position an
  # occurrence within its period, and the word for a working day.
  #
  # Inflection is the reason these lists are longer than the operator ones. A
  # German ordinal agrees with its noun and a French one with its gender, and
  # a lexicon that matches surface forms has to carry every form a person might
  # type. Listing them is dull and it is also the whole job — there is no
  # morphological analyser here, and adding one to save thirty words would be a
  # far larger thing to get wrong.
  @recurrence %{
    en: %{
      every: ["every", "each"],
      weekday: ["workday", "workdays", "weekday", "weekdays", "business"],
      # Word sets, each of which must appear in full. `day` and `week` together
      # catch "what day of the week is…" without claiming either word alone.
      day_of_week: [["day", "week"]],
      what: ["what"],
      ordinals: %{
        "first" => 1,
        "second" => 2,
        "third" => 3,
        "fourth" => 4,
        "fifth" => 5,
        "last" => -1
      }
    },
    de: %{
      # `jeden Montag`, `alle zwei Wochen`.
      every: ["jeden", "jede", "jedes", "alle"],
      weekday: ["werktag", "werktage", "arbeitstag", "arbeitstage"],
      day_of_week: [["wochentag"]],
      what: ["was", "wieviel"],
      # Strong and weak endings both, because both are written.
      ordinals: %{
        "erster" => 1,
        "erste" => 1,
        "ersten" => 1,
        "zweiter" => 2,
        "zweite" => 2,
        "zweiten" => 2,
        "dritter" => 3,
        "dritte" => 3,
        "dritten" => 3,
        "vierter" => 4,
        "vierte" => 4,
        "vierten" => 4,
        "fünfter" => 5,
        "fünfte" => 5,
        "fünften" => 5,
        "letzter" => -1,
        "letzte" => -1,
        "letzten" => -1
      }
    },
    fr: %{
      # `chaque lundi`, `tous les lundis`. `les` is noise and stays noise.
      every: ["chaque", "tous", "toutes"],
      # `jour ouvrable` and `jour ouvré` are two words each and the marker only
      # needs the one that carries the meaning.
      weekday: ["ouvrable", "ouvrables", "ouvré", "ouvrés"],
      day_of_week: [["jour", "semaine"]],
      what: ["quoi", "combien"],
      ordinals: %{
        "premier" => 1,
        "première" => 1,
        "deuxième" => 2,
        "second" => 2,
        "seconde" => 2,
        "troisième" => 3,
        "quatrième" => 4,
        "cinquième" => 5,
        "dernier" => -1,
        "dernière" => -1
      }
    },
    es: %{
      # `cada lunes`, `todos los martes`.
      every: ["cada", "todos", "todas"],
      weekday: ["laborable", "laborables", "hábil", "hábiles"],
      day_of_week: [["día", "semana"]],
      what: ["qué", "cuánto"],
      ordinals: %{
        "primer" => 1,
        "primero" => 1,
        "primera" => 1,
        "segundo" => 2,
        "segunda" => 2,
        "tercer" => 3,
        "tercero" => 3,
        "tercera" => 3,
        "cuarto" => 4,
        "cuarta" => 4,
        "quinto" => 5,
        "quinta" => 5,
        "último" => -1,
        "última" => -1
      }
    },
    ja: %{
      # `毎週月曜日` — "every week, Monday". The prefix is written joined to
      # what it repeats, so the segmenter has to split it off before any of
      # this matches; see the note in `LocalizePad.Temporal.Recurrence`.
      every: ["毎週", "毎月", "毎年", "毎日", "毎"],
      weekday: ["平日", "営業日"],
      # The segmenter splits 何曜日 into 何 and 曜日, so the set is the pair.
      day_of_week: [["何", "曜日"], ["何曜日"]],
      what: ["何"],
      ordinals: %{
        "第一" => 1,
        "第1" => 1,
        "第二" => 2,
        "第2" => 2,
        "第三" => 3,
        "第3" => 3,
        "第四" => 4,
        "第4" => 4,
        "第五" => 5,
        "第5" => 5,
        "最後" => -1,
        "最終" => -1
      }
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
    },
    fr: %{
      now: ["maintenant"],
      today: ["aujourd'hui"],
      tomorrow: ["demain"],
      yesterday: ["hier"]
    },
    es: %{
      now: ["ahora"],
      today: ["hoy"],
      # `mañana` is both "tomorrow" and "morning". Read as the date, which is
      # the reading a calculation wants; the other needs context this has none
      # of.
      tomorrow: ["mañana"],
      yesterday: ["ayer"]
    },
    ja: %{
      now: ["今"],
      today: ["今日"],
      tomorrow: ["明日"],
      yesterday: ["昨日"]
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
  Returns the deictic table for a locale.

  Used by the tokenizer to build a segmentation vocabulary for scripts written
  without word spaces.

  ### Arguments

  * `locale` - a locale identifier.

  ### Returns

  * A map of moment to surface forms.

  ### Examples

      iex> LocalizePad.Lexicon.deictics(:en) |> Map.fetch!(:today)
      ["today"]

  """
  @spec deictics(atom()) :: %{deictic() => [String.t()]}
  def deictics(locale \\ :en) do
    Map.get(@deictics, locale, @deictics.en)
  end

  @doc """
  Returns whether a word marks a phrase as recurring.

  ### Arguments

  * `word` - the surface form to test, already downcased.

  * `locale` - a locale identifier. Locales without an authored table fall
    back to `:en`.

  ### Returns

  * `true` or `false`.

  ### Examples

      iex> LocalizePad.Lexicon.every?("every", :en)
      true

      iex> LocalizePad.Lexicon.every?("jeden", :de)
      true

      iex> LocalizePad.Lexicon.every?("jeden", :en)
      false

  """
  @spec every?(String.t(), atom()) :: boolean()
  def every?(word, locale \\ :en) when is_binary(word) do
    word in recurrence(locale).every
  end

  @doc """
  Returns whether a word names a working day.

  ### Arguments

  * `word` - the surface form to test, already downcased.

  * `locale` - a locale identifier. Locales without an authored table fall
    back to `:en`.

  ### Returns

  * `true` or `false`.

  ### Examples

      iex> LocalizePad.Lexicon.weekday?("weekdays", :en)
      true

      iex> LocalizePad.Lexicon.weekday?("werktage", :de)
      true

  """
  @spec weekday?(String.t(), atom()) :: boolean()
  def weekday?(word, locale \\ :en) when is_binary(word) do
    word in recurrence(locale).weekday
  end

  @doc """
  Returns the position a spelled ordinal names, if any.

  Written ordinals — `4th`, `4.`, `4e` — are not here. Those reach the parser
  as `:ordinal` tokens, having been assembled from a number and its suffix by
  the tokenizer.

  ### Arguments

  * `word` - the surface form to look up, already downcased.

  * `locale` - a locale identifier. Locales without an authored table fall
    back to `:en`.

  ### Returns

  * `{:ok, position}`, where `-1` means the last. `:error` otherwise.

  ### Examples

      iex> LocalizePad.Lexicon.ordinal("fourth", :en)
      {:ok, 4}

      iex> LocalizePad.Lexicon.ordinal("letzten", :de)
      {:ok, -1}

      iex> LocalizePad.Lexicon.ordinal("dernière", :fr)
      {:ok, -1}

      iex> LocalizePad.Lexicon.ordinal("Tuesday", :en)
      :error

  """
  @spec ordinal(String.t(), atom()) :: {:ok, integer()} | :error
  def ordinal(word, locale \\ :en) when is_binary(word) do
    Map.fetch(recurrence(locale).ordinals, word)
  end

  @doc """
  Returns whether a word marks the unknown in a question.

  `what` in `180 is what % off 200`. The word is per locale like any other, but
  the phrasings that use it are English-shaped — see `LocalizePad.Inversion`,
  which is where vocabulary stops being enough.

  ### Arguments

  * `word` - the surface form to test, already downcased.

  * `locale` - a locale identifier. Locales without an authored table fall
    back to `:en`.

  ### Returns

  * `true` or `false`.

  ### Examples

      iex> LocalizePad.Lexicon.what?("what", :en)
      true

      iex> LocalizePad.Lexicon.what?("was", :de)
      true

      iex> LocalizePad.Lexicon.what?("200", :en)
      false

  """
  @spec what?(String.t(), atom()) :: boolean()
  def what?(word, locale \\ :en) when is_binary(word) do
    word in Map.get(recurrence(locale), :what, [])
  end

  @doc """
  Returns whether the words name a "which day of the week" question.

  Matched as word *sets* rather than single markers, because the question is a
  compound in most languages — `day` and `week` in English, `jour` and
  `semaine` in French — and claiming either word alone would swallow far too
  many ordinary lines.

  German is why this is separate from `weekday?/2` at all: `Werktag` is a
  working day and `Wochentag` a day of the week, and a table that flattened
  them would answer the wrong one of the two questions.

  ### Arguments

  * `words` - the line's words, already downcased.

  * `locale` - a locale identifier. Locales without an authored table fall
    back to `:en`.

  ### Returns

  * `true` or `false`.

  ### Examples

      iex> LocalizePad.Lexicon.day_of_week?(~w(what day of the week is it), :en)
      true

      iex> LocalizePad.Lexicon.day_of_week?(~w(welcher wochentag), :de)
      true

      iex> LocalizePad.Lexicon.day_of_week?(~w(is it a workday), :en)
      false

  """
  @spec day_of_week?([String.t()], atom()) :: boolean()
  def day_of_week?(words, locale \\ :en) when is_list(words) do
    locale
    |> recurrence()
    |> Map.get(:day_of_week, [])
    |> Enum.any?(fn required -> Enum.all?(required, &(&1 in words)) end)
  end

  @doc """
  Returns the recurrence table for a locale.

  Used by the tokenizer to build a segmentation vocabulary for scripts written
  without word spaces.

  ### Arguments

  * `locale` - a locale identifier.

  ### Returns

  * A map with `:every`, `:weekday` and `:ordinals` keys.

  ### Examples

      iex> LocalizePad.Lexicon.recurrence(:en).every
      ["every", "each"]

  """
  @spec recurrence(atom()) :: map()
  def recurrence(locale \\ :en) do
    Map.get(@recurrence, locale, @recurrence.en)
  end

  @doc """
  Returns the locales that have an authored lexicon.

  ### Returns

  * A list of locale identifiers.

  ### Examples

      iex> LocalizePad.Lexicon.known_locales()
      [:de, :en, :es, :fr, :ja]

  """
  @spec known_locales() :: [atom()]
  def known_locales do
    @lexicons |> Map.keys() |> Enum.sort()
  end
end
