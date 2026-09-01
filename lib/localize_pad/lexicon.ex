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

  alias LocalizePad.Locales

  @type role ::
          :to
          | :per
          | :after
          | :before
          | :of
          | :off
          | :on
          | :intersect
          | :of_reversed
          | :per_reversed

  @type aggregate :: :sum | :average | :median | :count | :minimum | :maximum

  @type deictic ::
          :now | :today | :tomorrow | :yesterday | :day_after_tomorrow | :day_before_yesterday

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
      # miles" — and `を` happens to sit *between* the two operands in the same
      # order English uses, so an infix parser can take it as-is.
      to: ["を", "は", "→"],
      after: ["後"],
      before: ["前"],
      intersect: ["と", "∩"],

      # These two do not have that luck. `の` is a genitive: `700の20%` is
      # "700's 20%", so the whole comes *first* where English puts it last.
      # `あたり` is the same shape — `1日あたり100` is "100 per day", not "1 day
      # per 100", and reading it in English order answered 0.01.
      #
      # Recorded as their own roles rather than corrected in the evaluator,
      # because the reversal is a fact about Japanese and the evaluator has no
      # locale. See `LocalizePad.Parser`, which swaps the operands.
      of_reversed: ["の"],
      per_reversed: ["あたり", "ごと"]
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
      # Only what the rule sets cannot spell. `last` is a position rather than
      # an ordinal number, so no locale spells it and every locale needs it.
      ordinals: %{
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
        "letzte" => -1,
        "letzten" => -1,
        "letzter" => -1
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
      # `second` is a synonym for `deuxième` rather than a form of it, so the
      # rule sets do not produce it.
      ordinals: %{
        "dernier" => -1,
        "dernière" => -1,
        "second" => 2,
        "seconde" => 2
      }
    },
    es: %{
      # `cada lunes`, `todos los martes`.
      every: ["cada", "todos", "todas"],
      weekday: ["laborable", "laborables", "hábil", "hábiles"],
      day_of_week: [["día", "semana"]],
      what: ["qué", "cuánto"],
      ordinals: %{
        "última" => -1,
        "último" => -1
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
      # `第1` is the Arabic-numeral form. The rule sets spell `第一` and its
      # siblings, but a reader typing digits writes these.
      ordinals: %{
        "第1" => 1,
        "第2" => 2,
        "第3" => 3,
        "第4" => 4,
        "第5" => 5,
        "最後" => -1,
        "最終" => -1
      }
    }
  }

  # The words that summarise the entries above them. Soulver uses a keystroke
  # for a subtotal; a pad that has to survive being pasted into a chat window
  # needs a word you can type — and it has to be a word in the reader's
  # language, or a German sheet cannot add itself up.
  #
  # `total` appears in more than one language because more than one language
  # borrowed it. `mean` and `average` are the same function under two names,
  # which is why the table maps a function to its surface forms rather than the
  # other way round.
  #
  # Spanish is the reminder that these are near neighbours in every language:
  # `media` is the average and `mediana` is the median, one letter apart and
  # two different answers.
  #
  # `min` is also the abbreviation for a minute, so a line reading nothing but
  # `min` answers the smallest entry above it rather than one minute. Only a
  # line that is *entirely* the word is read this way — `5 min` is still five
  # minutes — and nobody writes a bare `min` meaning a duration.
  @aggregates %{
    en: %{
      sum: ["sum", "subtotal", "total"],
      average: ["average", "avg", "mean"],
      median: ["median"],
      count: ["count"],
      minimum: ["min", "minimum", "lowest", "smallest"],
      maximum: ["max", "maximum", "highest", "largest"]
    },
    de: %{
      sum: ["summe", "zwischensumme", "gesamt", "gesamtsumme", "total"],
      average: ["durchschnitt", "mittelwert", "mittel"],
      median: ["median", "zentralwert"],
      count: ["anzahl"],
      minimum: ["min", "minimum", "kleinster wert"],
      maximum: ["max", "maximum", "größter wert", "grösster wert"]
    },
    fr: %{
      sum: ["somme", "sous-total", "total"],
      average: ["moyenne"],
      median: ["médiane", "mediane"],
      count: ["compte", "nombre"],
      minimum: ["min", "minimum"],
      maximum: ["max", "maximum"]
    },
    es: %{
      sum: ["suma", "subtotal", "total"],
      average: ["promedio", "media"],
      median: ["mediana"],
      count: ["cuenta", "recuento"],
      minimum: ["min", "mínimo", "minimo"],
      maximum: ["max", "máximo", "maximo"]
    },
    ja: %{
      sum: ["合計", "小計", "計"],
      average: ["平均", "平均値"],
      median: ["中央値", "メジアン"],
      count: ["件数", "個数", "カウント"],
      minimum: ["最小", "最小値"],
      maximum: ["最大", "最大値"]
    }
  }

  @doc """
  The function a word names, when that word is alone on a line.

  ### Arguments

  * `word` - the line's whole text, trimmed.

  * `locale` - the locale whose vocabulary to read.

  ### Returns

  * `{:ok, function}` where function is `:sum`, `:average`, `:median`,
    `:count`, `:minimum` or `:maximum`.

  * `:error` when the word names no function in this locale, which is what
    makes `somme` a calculation on a French sheet and prose on an English one.

  ### Examples

      iex> LocalizePad.Lexicon.aggregate("sum", :en)
      {:ok, :sum}

      iex> LocalizePad.Lexicon.aggregate("Mean", :en)
      {:ok, :average}

      iex> LocalizePad.Lexicon.aggregate("Durchschnitt", :de)
      {:ok, :average}

      iex> LocalizePad.Lexicon.aggregate("breakfast", :en)
      :error

  """
  @spec aggregate(String.t(), Locales.locale()) :: {:ok, aggregate()} | :error
  def aggregate(word, locale \\ :en) when is_binary(word) do
    word = String.downcase(word)

    @aggregates
    |> Map.get(language(locale), @aggregates.en)
    |> Enum.find_value(:error, fn {function, words} ->
      if word in words, do: {:ok, function}
    end)
  end

  # The events `LocalizePad.Almanac` answers for, in the reader's own words.
  #
  # Most are compounds — `Sonnenaufgang`, `lever du soleil`, `salida del sol`,
  # `日の出` — so a form here may be one word or several, and both are matched
  # against the line rather than against a single token.
  #
  # Japanese is why the unspaced line is searched as well as the spaced one.
  # The segmenter's dictionary knows `日の出` and hands it back whole, but
  # splits `月の出` into three tokens and `月相` into two, so a form written the
  # way a reader types it would otherwise match one and miss the others. Only
  # forms with no Latin letters are looked for that way: joining an English
  # line's words would make `the sun set` contain `sunset`.
  @almanac %{
    en: %{
      sunrise: ["sunrise", "sunup", "dawn"],
      sunset: ["sunset", "sundown", "dusk"],
      moonrise: ["moonrise"],
      moonset: ["moonset"],
      moon_phase: ["moon phase", "phase of the moon", "lunar phase", "moonphase"]
    },
    de: %{
      sunrise: ["sonnenaufgang", "morgendämmerung"],
      sunset: ["sonnenuntergang", "abenddämmerung"],
      moonrise: ["mondaufgang"],
      moonset: ["monduntergang"],
      moon_phase: ["mondphase", "mondphasen"]
    },
    fr: %{
      sunrise: ["lever du soleil", "lever de soleil", "aube", "aurore"],
      sunset: ["coucher du soleil", "coucher de soleil", "crépuscule"],
      moonrise: ["lever de la lune", "lever de lune"],
      moonset: ["coucher de la lune", "coucher de lune"],
      moon_phase: ["phase de la lune", "phase lunaire"]
    },
    es: %{
      sunrise: ["amanecer", "salida del sol", "alba", "aurora"],
      sunset: ["atardecer", "puesta del sol", "ocaso", "anochecer"],
      moonrise: ["salida de la luna"],
      moonset: ["puesta de la luna"],
      moon_phase: ["fase lunar", "fase de la luna"]
    },
    ja: %{
      sunrise: ["日の出", "日出"],
      sunset: ["日の入り", "日の入", "日没"],
      moonrise: ["月の出"],
      moonset: ["月の入り", "月の入", "月没"],
      moon_phase: ["月相", "月の満ち欠け"]
    }
  }

  @doc """
  The sun or moon event a line names, if it names one.

  ### Arguments

  * `words` - the line's words, in order.

  * `locale` - the locale whose vocabulary to read.

  ### Returns

  * `{:ok, event}` where event is `:sunrise`, `:sunset`, `:moonrise`,
    `:moonset` or `:moon_phase`.

  * `:error` when the line names none, which is nearly every line.

  ### Examples

      iex> LocalizePad.Lexicon.almanac_event(["sunrise", "tomorrow"], :en)
      {:ok, :sunrise}

      iex> LocalizePad.Lexicon.almanac_event(["lever", "du", "soleil"], :fr)
      {:ok, :sunrise}

      iex> LocalizePad.Lexicon.almanac_event(["月", "の", "出"], :ja)
      {:ok, :moonrise}

      iex> LocalizePad.Lexicon.almanac_event(["breakfast"], :en)
      :error

  """
  @spec almanac_event([String.t()], Locales.locale()) :: {:ok, atom()} | :error
  def almanac_event(words, locale \\ :en) when is_list(words) do
    words = Enum.map(words, &String.downcase/1)
    spaced = Enum.join(words, " ")
    tight = Enum.join(words)

    @almanac
    |> Map.get(language(locale), @almanac.en)
    |> almanac_forms()
    |> Enum.find_value(:error, fn {form, event} ->
      if names_event?(form, words, spaced, tight), do: {:ok, event}
    end)
  end

  # Longest first, so `phase of the moon` is read as the phase rather than
  # `moon` alone being caught by a shorter form.
  defp almanac_forms(table) do
    for({event, forms} <- table, form <- forms, do: {form, event})
    |> Enum.sort_by(fn {form, _event} -> -String.length(form) end)
  end

  defp names_event?(form, words, spaced, tight) do
    cond do
      String.contains?(form, " ") -> String.contains?(spaced, form)
      form in words -> true
      latin_script?(form) -> false
      true -> String.contains?(tight, form)
    end
  end

  defp latin_script?(form), do: String.match?(form, ~r/[a-z]/u)

  # The words `LocalizePad.Trip` is built from: the noun that opens an
  # itinerary, the words that close one, the units a stay is counted in, and
  # the preposition that puts a stay somewhere.
  #
  # `at` is its own list rather than the `:to` role because the two disagree.
  # French says `3 nuits à Paris` and converts with `en`, so adding `à` to the
  # conversion role to serve trips would change what `3 mètres à pieds` means.
  # Japanese marks the place with `に`, which sits *after* it — see
  # `LocalizePad.Trip` on why that order is read only inside a trip.
  @trip %{
    en: %{
      opens: ["trip", "itinerary"],
      ends: ["end", "ends", "ending", "finish", "finishes", "finishing"],
      stays: ["night", "nights", "day", "days"],
      at: ["in", "at"]
    },
    de: %{
      opens: ["reise"],
      ends: ["endet", "ende", "endend", "schluss"],
      stays: ["nacht", "nächte", "naechte", "tag", "tage"],
      at: ["in"]
    },
    fr: %{
      opens: ["voyage"],
      ends: ["fin", "finit", "termine", "termine le"],
      stays: ["nuit", "nuits", "jour", "jours"],
      at: ["à", "a", "en"]
    },
    es: %{
      opens: ["viaje"],
      ends: ["fin", "termina", "acaba"],
      stays: ["noche", "noches", "día", "dia", "días", "dias"],
      at: ["en"]
    },
    ja: %{
      opens: ["旅程", "旅行"],
      ends: ["終了", "まで"],
      stays: ["泊", "日"],
      at: ["に", "で"]
    }
  }

  @doc """
  The trip vocabulary for a locale.

  ### Arguments

  * `locale` - the locale whose vocabulary to read.

  ### Returns

  * A map with `:opens`, `:ends`, `:stays` and `:at`, each a list of lowercased
    forms.

  ### Examples

      iex> LocalizePad.Lexicon.trip(:de).opens
      ["reise"]

      iex> "nuits" in LocalizePad.Lexicon.trip(:fr).stays
      true

  """
  @spec trip(Locales.locale()) :: %{
          opens: [String.t()],
          ends: [String.t()],
          stays: [String.t()],
          at: [String.t()]
        }
  def trip(locale \\ :en) do
    Map.get(@trip, language(locale), @trip.en)
  end

  # The taxes a sheet can name. Every territory calls its own something else,
  # and the abbreviation is what people write: `VAT` in Britain, `MwSt` in
  # Germany, `TVA` in France, `IVA` in Spain, `消費税` in Japan.
  #
  # The English list travels with each of them. A tax is written on invoices
  # that cross borders, and somebody reading a German sheet with a British
  # invoice beside it types what the invoice says.
  @taxes %{
    en: ["vat", "gst", "sales tax"],
    de: ["mwst", "mwst.", "mehrwertsteuer", "ust", "umsatzsteuer", "vat"],
    fr: ["tva", "vat"],
    es: ["iva", "vat"],
    ja: ["消費税", "vat"]
  }

  # `circa 1955`. The qualifier that says a year is approximate, and the marker
  # that puts it before the common era.
  @uncertainty %{
    en: %{approximate: ["circa", "about", "approximately", "around"], before_era: ["bce", "bc"]},
    de: %{
      approximate: ["circa", "ca", "ca.", "etwa", "ungefähr", "gegen"],
      before_era: ["v.chr.", "vchr", "bce", "bc"]
    },
    fr: %{
      approximate: ["circa", "environ", "vers", "approximativement"],
      before_era: ["av.j.-c.", "avjc", "bce", "bc"]
    },
    es: %{
      approximate: ["circa", "hacia", "aproximadamente", "alrededor"],
      before_era: ["a.c.", "ac", "bce", "bc"]
    },
    ja: %{approximate: ["約", "頃", "ごろ", "circa"], before_era: ["紀元前", "bce", "bc"]}
  }

  @doc """
  Whether a word names a sales tax.

  ### Arguments

  * `word` - the word to test.

  * `locale` - the locale whose vocabulary to read.

  ### Returns

  * `true` or `false`.

  ### Examples

      iex> LocalizePad.Lexicon.tax?("VAT", :en)
      true

      iex> LocalizePad.Lexicon.tax?("MwSt", :de)
      true

      iex> LocalizePad.Lexicon.tax?("breakfast", :en)
      false

  """
  @spec tax?(String.t(), Locales.locale()) :: boolean()
  def tax?(word, locale \\ :en) when is_binary(word) do
    String.downcase(word) in Map.get(@taxes, language(locale), @taxes.en)
  end

  @doc """
  The words that qualify a year as uncertain.

  ### Arguments

  * `locale` - the locale whose vocabulary to read.

  ### Returns

  * A map with `:approximate` and `:before_era`, each a list of lowercased
    forms.

  ### Examples

      iex> "ungefähr" in LocalizePad.Lexicon.uncertainty(:de).approximate
      true

      iex> "紀元前" in LocalizePad.Lexicon.uncertainty(:ja).before_era
      true

  """
  @spec uncertainty(Locales.locale()) :: %{approximate: [String.t()], before_era: [String.t()]}
  def uncertainty(locale \\ :en) do
    Map.get(@uncertainty, language(locale), @uncertainty.en)
  end

  # The financial phrases. Only the nouns and qualifiers are here, because only
  # they are words: the amount, the rate and the term are recognised by *type*
  # — one money token, one percentage, one duration — and a type is the same in
  # every language. That is why a page of vocabulary buys the whole feature.
  #
  # `present value` is two words in English and French and one in German, so
  # the forms are matched as written rather than assembled from a pair.
  @finance %{
    en: %{
      repayment: ["repayment", "repayments"],
      interest: ["interest"],
      present_value: ["present value"],
      joins: ["after", "at", "@", "over", "for"],
      total: ["total"],
      compounding: ["compounding", "compounded"],
      frequencies: %{
        "daily" => :daily,
        "weekly" => :weekly,
        "monthly" => :monthly,
        "quarterly" => :quarterly,
        "annual" => :annually,
        "annually" => :annually,
        "yearly" => :annually
      }
    },
    de: %{
      repayment: ["rate", "raten", "tilgung", "annuität"],
      interest: ["zinsen", "zins"],
      present_value: ["barwert", "gegenwartswert"],
      joins: ["nach", "bei", "über", "für", "zu", "@"],
      total: ["gesamt", "insgesamt"],
      compounding: ["verzinst", "zinseszins"],
      frequencies: %{
        "täglich" => :daily,
        "wöchentlich" => :weekly,
        "monatlich" => :monthly,
        "monatliche" => :monthly,
        "vierteljährlich" => :quarterly,
        "jährlich" => :annually,
        "jährliche" => :annually
      }
    },
    fr: %{
      repayment: ["mensualité", "remboursement", "échéance"],
      interest: ["intérêt", "intérêts"],
      present_value: ["valeur actuelle", "valeur présente"],
      joins: ["après", "à", "sur", "pendant", "pour", "@"],
      total: ["total"],
      compounding: ["composé", "capitalisé"],
      frequencies: %{
        "quotidien" => :daily,
        "quotidienne" => :daily,
        "hebdomadaire" => :weekly,
        "mensuel" => :monthly,
        "mensuelle" => :monthly,
        "trimestriel" => :quarterly,
        "trimestrielle" => :quarterly,
        "annuel" => :annually,
        "annuelle" => :annually
      }
    },
    es: %{
      repayment: ["cuota", "pago", "amortización"],
      interest: ["interés", "intereses"],
      present_value: ["valor actual", "valor presente"],
      joins: ["después", "a", "en", "durante", "por", "@"],
      total: ["total"],
      compounding: ["compuesto", "capitalizado"],
      frequencies: %{
        "diario" => :daily,
        "diaria" => :daily,
        "semanal" => :weekly,
        "mensual" => :monthly,
        "trimestral" => :quarterly,
        "anual" => :annually
      }
    },
    ja: %{
      repayment: ["返済", "返済額"],
      interest: ["利息", "金利"],
      present_value: ["現在価値"],
      joins: ["後", "で", "@"],
      total: ["合計", "総額"],
      compounding: ["複利"],
      frequencies: %{
        "毎日" => :daily,
        "毎週" => :weekly,
        "毎月" => :monthly,
        "月々" => :monthly,
        "四半期" => :quarterly,
        "毎年" => :annually,
        "年間" => :annually
      }
    }
  }

  @doc """
  The financial vocabulary for a locale.

  ### Arguments

  * `locale` - the locale whose vocabulary to read.

  ### Returns

  * A map with `:repayment`, `:interest`, `:present_value`, `:joins`,
    `:total` and `:compounding` — each a list of lowercased forms — and
    `:frequencies`, a map from form to `:daily`, `:weekly`, `:monthly`,
    `:quarterly` or `:annually`.

  ### Examples

      iex> "zinsen" in LocalizePad.Lexicon.finance(:de).interest
      true

      iex> LocalizePad.Lexicon.finance(:fr).frequencies["mensuelle"]
      :monthly

  """
  @spec finance(Locales.locale()) :: map()
  def finance(locale \\ :en) do
    Map.get(@finance, language(locale), @finance.en)
  end

  # Words that name the reader's own units as a conversion target: `42 km in
  # preferred units`. The answer comes from CLDR's unit preferences for the
  # sheet's territory, so `en-AU` keeps kilometres where `en-US` gets miles.
  #
  # `preferred` first because it is CLDR's own word for this, and it says what
  # the answer depends on. `local` reads well too and both are kept: a sheet
  # already written with one must not stop working because the other reads
  # better.
  #
  # Single words only, deliberately. `local units` and `unités locales` then
  # work without a multi-word matcher, because the second word falls through as
  # trailing prose the way `19 + 22 for breakfast` already does.
  #
  # These are *targets*, not operators, so they sit here rather than in the
  # role table — the same reason `today` does.
  @preferences %{
    en: ["preferred", "local", "locally"],
    de: ["bevorzugt", "bevorzugte", "bevorzugten", "lokal", "lokale", "lokalen", "ortsüblich"],
    fr: ["préféré", "préférée", "préférés", "préférées", "local", "locale", "locales"],
    es: ["preferido", "preferida", "preferidos", "preferidas", "local", "locales"],
    ja: ["優先", "現地", "ローカル"]
  }

  # What the quantity is *for*, which is the other half of what CLDR needs to
  # pick a unit. The territory alone says an American measures length in feet;
  # the usage is what makes 1.8 m come back as `5 foot 10.87 inch` rather than
  # `5.91 foot`, and what gives a British weight in stone.
  #
  # These words are only read as usages directly after the preference word —
  # `in local height units`, never `height` on its own. That is what keeps
  # `height = 1.8 m` a declaration: a calculator whose vocabulary quietly
  # claimed `height`, `weight` and `floor` would break more sheets than the
  # feature is worth.
  @usages %{
    en: %{
      # Not a CLDR unit usage but the same shape of question: what the reader
      # wants the answer expressed in. `in preferred currency` converts money
      # the way `in preferred units` converts a quantity.
      "currency" => :currency,
      "height" => :person_height,
      "weight" => :person,
      "body" => :person,
      "fluid" => :fluid,
      "drink" => :fluid,
      "road" => :road,
      "land" => :land,
      "floor" => :floor_space
    },
    de: %{
      "währung" => :currency,
      "körpergröße" => :person_height,
      "größe" => :person_height,
      "gewicht" => :person,
      "flüssigkeit" => :fluid,
      "straße" => :road,
      "land" => :land,
      "wohnfläche" => :floor_space
    },
    fr: %{
      "devise" => :currency,
      "monnaie" => :currency,
      "taille" => :person_height,
      "poids" => :person,
      "liquide" => :fluid,
      "route" => :road,
      "terrain" => :land,
      "surface" => :floor_space
    },
    es: %{
      "moneda" => :currency,
      "altura" => :person_height,
      "peso" => :person,
      "líquido" => :fluid,
      "carretera" => :road,
      "terreno" => :land,
      "superficie" => :floor_space
    },
    ja: %{
      "通貨" => :currency,
      "身長" => :person_height,
      "体重" => :person,
      "液体" => :fluid,
      "道路" => :road,
      "土地" => :land
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
  @spec deictic(String.t(), Locales.locale()) :: {:ok, deictic()} | :error
  def deictic(word, locale \\ :en) when is_binary(word) do
    downcased = String.downcase(word)

    locale
    |> deictics()
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
  @spec role(String.t(), Locales.locale()) :: {:ok, role()} | :error
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
  @spec lexicon(Locales.locale()) :: %{role() => [String.t()]}
  def lexicon(locale \\ :en) do
    Map.get(@lexicons, language(locale), @lexicons.en)
  end

  @doc """
  Every surface form this locale had to be told, rather than read from CLDR.

  TEMPORARY, for a demo — see the toggle in `LocalizePadWeb.SheetLive`.

  The five authored tables and nothing else: the operator lexicon, the
  recurrence words a rule set cannot spell, preference targets, usages and the
  totalling words. It deliberately excludes everything `build_recurrence/1` and
  `build_deictics/1` derive, so `heute` and `zweiter` do not appear while
  `jeden` and `letzte` do — which is the distinction being shown.

  ### Arguments

  * `locale` - the locale whose authored vocabulary is wanted.

  ### Returns

  * A `MapSet` of lowercased forms.

  ### Examples

      iex> authored = LocalizePad.Lexicon.authored(:en)
      iex> MapSet.member?(authored, "every")
      true

      iex> authored = LocalizePad.Lexicon.authored(:en)
      iex> MapSet.member?(authored, "friday")
      false

  """
  @spec authored(Locales.locale()) :: MapSet.t(String.t())
  def authored(locale \\ :en) do
    language = language(locale)
    recurrence = Map.get(@recurrence, language, @recurrence.en)

    [
      @lexicons |> Map.get(language, @lexicons.en) |> Map.values() |> List.flatten(),
      recurrence.every,
      recurrence.weekday,
      recurrence.what,
      List.flatten(recurrence.day_of_week),
      Map.keys(recurrence.ordinals),
      @aggregates |> Map.get(language, @aggregates.en) |> Map.values() |> List.flatten(),
      Map.get(@preferences, language, @preferences.en),
      @usages |> Map.get(language, @usages.en) |> Map.keys(),
      # Split, because a form may be several words — `lever du soleil` is three
      # — and what the underline marks is words.
      @almanac
      |> Map.get(language, @almanac.en)
      |> Map.values()
      |> List.flatten()
      |> Enum.flat_map(&String.split/1),
      @trip |> Map.get(language, @trip.en) |> Map.values() |> List.flatten(),
      Map.get(@taxes, language, @taxes.en),
      @finance
      |> Map.get(language, @finance.en)
      |> Map.drop([:frequencies])
      |> Map.values()
      |> List.flatten()
      |> Enum.flat_map(&String.split/1),
      @finance |> Map.get(language, @finance.en) |> Map.fetch!(:frequencies) |> Map.keys(),
      @uncertainty |> Map.get(language, @uncertainty.en) |> Map.values() |> List.flatten()
      # CLDR supplies the rest: month and weekday names, unit names, currency
      # symbols and the words for a calendar unit, so a duration and an amount
      # are read in every locale without a word of them being written here.
    ]
    |> List.flatten()
    |> Enum.map(&String.downcase/1)
    |> MapSet.new()
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
  @spec deictics(Locales.locale()) :: %{deictic() => [String.t()]}
  def deictics(locale \\ :en) do
    id = Localize.Locale.cldr_locale_id_from(locale)
    key = {__MODULE__, :deictics, id}

    case :persistent_term.get(key, nil) do
      nil ->
        built = build_deictics(locale)
        :persistent_term.put(key, built)
        built

      built ->
        built
    end
  end

  # `today`, `tomorrow` and `yesterday` are CLDR's relative day names, and
  # `now` is the relative *second*. Both live in `date_fields`, where they are
  # written for every locale by people who speak it — so this table used to be
  # four words per locale transcribed from data already downloaded.
  #
  # CLDR carries more than was transcribed: German also has `vorgestern` and
  # `übermorgen`, which are read here as the days they name.
  defp build_deictics(locale) do
    day = relative(locale, :day)
    second = relative(locale, :second)

    %{
      now: forms(second[0]),
      today: forms(day[0]),
      tomorrow: forms(day[1]),
      yesterday: forms(day[-1]),
      day_after_tomorrow: forms(day[2]),
      day_before_yesterday: forms(day[-2])
    }
  end

  defp relative(locale, field) do
    case Localize.Locale.get(locale, [:date_fields, field, :standard, :relative_ordinal]) do
      {:ok, relatives} when is_map(relatives) -> relatives
      _absent -> %{}
    end
  end

  defp forms(nil), do: []
  defp forms(word) when is_binary(word), do: [String.downcase(word)]

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
  @spec every?(String.t(), Locales.locale()) :: boolean()
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
  @spec weekday?(String.t(), Locales.locale()) :: boolean()
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
  @spec ordinal(String.t(), Locales.locale()) :: {:ok, integer()} | :error
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
  @spec what?(String.t(), Locales.locale()) :: boolean()
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
  @spec day_of_week?([String.t()], Locales.locale()) :: boolean()
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
  @spec recurrence(Locales.locale()) :: map()
  def recurrence(locale \\ :en) do
    id = Localize.Locale.cldr_locale_id_from(locale)
    key = {__MODULE__, :recurrence, id}

    case :persistent_term.get(key, nil) do
      nil ->
        built = build_recurrence(locale)
        :persistent_term.put(key, built)
        built

      built ->
        built
    end
  end

  # Two of these four come from CLDR now.
  #
  # The spelled ordinals are generated from the locale's own RBNF rule sets,
  # which is where the inflections live: German has `spellout_ordinal` and four
  # more for its cases, French has masculine, feminine and their plurals, and
  # Spanish has no plain set at all. Generating across all of them produces 25
  # German forms where 18 were written by hand — `erstem` and `erstes` are
  # recognised now and were not.
  #
  # `day_of_week` is CLDR's own field name for the concept: "Wochentag",
  # "jour de la semaine", "曜日". The word sets it produces are what the
  # matcher already expects.
  #
  # What stays authored is `every`, the working-day words, and `last`. `last`
  # is not an ordinal number but a position, and no rule set spells it; the
  # working-day words are not in CLDR at all — `Werktag` appears nowhere in
  # the whole common tree, because CLDR models which days are the weekend and
  # not what the concept is called.
  defp build_recurrence(locale) do
    authored = Map.get(@recurrence, language(locale), @recurrence.en)

    %{
      authored
      | ordinals: Map.merge(generated_ordinals(locale), authored.ordinals),
        day_of_week: Enum.uniq(authored.day_of_week ++ derived_day_of_week(locale))
    }
  end

  # 1 to 5 across every ordinal rule set the locale has. Anything the locale
  # cannot spell is simply absent rather than guessed at.
  @ordinal_positions 1..5

  defp generated_ordinals(locale) do
    for position <- @ordinal_positions,
        format <- ordinal_formats(locale),
        {:ok, spelled} <- [Localize.Number.to_string(position, locale: locale, format: format)],
        into: %{} do
      {String.downcase(spelled), position}
    end
  end

  defp ordinal_formats(locale) do
    case Localize.Locale.get(locale, [:rbnf]) do
      {:ok, rbnf} ->
        rbnf
        |> Map.values()
        |> Enum.flat_map(&Map.keys/1)
        |> Enum.filter(&String.starts_with?(to_string(&1), "spellout_ordinal"))

      _absent ->
        []
    end
  end

  # CLDR writes the field name as a phrase — "day of the week" — and the
  # matcher wants the words that carry it. Short words are dropped because
  # `of` and `the` are in every English sentence and would match anything.
  defp derived_day_of_week(locale) do
    case Localize.Locale.get(locale, [:date_fields, :weekday, :standard, :display_name]) do
      {:ok, name} ->
        words =
          name
          |> String.downcase()
          |> String.split(~r/\s+/u, trim: true)
          |> Enum.filter(&(String.length(&1) > 2))

        if words == [], do: [], else: [words]

      _absent ->
        []
    end
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

  @doc """
  Whether a word asks for the answer in the reader's own units.

  Lookup is case-insensitive.

  ### Arguments

  * `word` - the surface form to look up.

  * `locale` - the locale whose vocabulary to read.

  ### Returns

  * `true` or `false`.

  ### Examples

      iex> LocalizePad.Lexicon.preference?("local", :en)
      true

      iex> LocalizePad.Lexicon.preference?("lokal", :de)
      true

      iex> LocalizePad.Lexicon.preference?("kilometer", :en)
      false

  """
  @spec preference?(String.t(), Locales.locale()) :: boolean()
  def preference?(word, locale \\ :en) when is_binary(word) do
    String.downcase(word) in Map.get(@preferences, language(locale), @preferences.en)
  end

  @doc """
  What a word says the quantity is used for, if anything.

  Only meaningful directly after a preference word — see `preference?/2`.
  Lookup is case-insensitive.

  ### Arguments

  * `word` - the surface form to look up.

  * `locale` - the locale whose vocabulary to read.

  ### Returns

  * `{:ok, usage}` where usage is a CLDR unit-preference usage.

  * `:error` when the word names no usage.

  ### Examples

      iex> LocalizePad.Lexicon.usage("height", :en)
      {:ok, :person_height}

      iex> LocalizePad.Lexicon.usage("Gewicht", :de)
      {:ok, :person}

      iex> LocalizePad.Lexicon.usage("units", :en)
      :error

  """
  @spec usage(String.t(), Locales.locale()) :: {:ok, atom()} | :error
  def usage(word, locale \\ :en) when is_binary(word) do
    @usages
    |> Map.get(language(locale), @usages.en)
    |> Map.fetch(String.downcase(word))
  end

  # The tables above are keyed by language, and a sheet carries a whole
  # language tag. The language subtag rather than `cldr_locale_id`, because
  # vocabulary is a property of the language: `de-AT` says `von` exactly as
  # `de` does, and keying on the resolved data file would send `en-AU` to
  # English by luck and a future `de-AT` table to English by mistake.
  #
  # Bare atoms and strings are still accepted, since tests and doctests pass
  # `:en` and it would be perverse to make them build a tag first. They are
  # resolved rather than used as keys directly: `Map.get(@lexicons, "de", ...)`
  # misses and falls through to English, which would cost a German sheet its
  # German operator words without failing anything.
  defp language(%Localize.LanguageTag{language: language}), do: language

  defp language(locale) when is_atom(locale) and not is_nil(locale) do
    if Map.has_key?(@lexicons, locale), do: locale, else: resolve_language(locale)
  end

  defp language(locale), do: resolve_language(locale)

  defp resolve_language(locale) do
    case Localize.validate_locale(locale) do
      {:ok, language_tag} -> language_tag.language
      {:error, _reason} -> :en
    end
  end
end
