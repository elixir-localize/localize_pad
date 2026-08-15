defmodule LocalizePad.Tokenizer do
  @moduledoc """
  Turns a line of text into a list of `LocalizePad.Token`.

  ## The forgiving part

  The defining property of a notepad calculator is that prose and calculation
  mix freely, and words the engine does not recognise are *discarded rather
  than fatal*. `$19 for breakfast + $22 for the uber` is a working line whose
  answer is 41; `for breakfast` and `for the uber` simply carry no arithmetic
  meaning. This module therefore never fails on unrecognised input — words it
  cannot classify become `:word` tokens and the parser decides whether they are
  variable references or noise.

  ## Numbers come first, and they come from CLDR

  Number extraction is delegated to `Localize.Number.Parser.scan/2`, which
  splits a string into numbers and text runs using the locale's own decimal and
  grouping separators and transliterating non-Latin digits. This is what makes
  `1.234,5 Meter` read as 1234.5 under `:de` and as something quite different
  under `:en` — and it is why the locale must be threaded through every call
  rather than assumed.

  ## Ambiguity is preserved, not resolved

  Where a word has more than one reading — `in` as the conversion keyword and
  as `inch` — both are recorded on the token. See `LocalizePad.Token`.

  ## Source offsets

  Tokens carry the text they were read from but not yet their offset into the
  line. Offsets are needed for editor decoration (syntax highlighting,
  hover-to-peek, click-an-answer-to-reference) and will be added with the
  CodeMirror editor; reconstructing them from `scan/2` output is unreliable
  because a number's source text is not recoverable from its value (`"02"` and
  `"2"` both parse to `2`).

  """

  alias LocalizePad.{Currency, Lexicon, SalesTax, Token, Units}
  alias LocalizePad.Temporal.{Calendars, Scanner, Zones}

  # Multi-character operators must be tried before their single-character
  # prefixes, hence "->" and "**" first. The `u` modifier is required: without
  # it the character class matches bytes, and `×` (two UTF-8 bytes) is torn in
  # half rather than recognised.
  @operator_pattern ~r/(->|\*\*|[+\-*\/^()=,;×÷%])/u

  @operators %{
    "+" => :plus,
    "-" => :minus,
    "*" => :times,
    "×" => :times,
    "**" => :power,
    "/" => :divide,
    "÷" => :divide,
    "^" => :power,
    "(" => :lparen,
    ")" => :rparen,
    "=" => :assign,
    "," => :comma,
    ";" => :semicolon,
    "%" => :percent
  }

  @doc """
  Tokenizes a line of text.

  ### Arguments

  * `input` - the line to tokenize.

  * `options` - a keyword list of options.

  ### Options

  * `:locale` - the locale whose number format and operator lexicon apply.
    Defaults to `Localize.get_locale/0`.

  ### Returns

  * `{:ok, tokens}`. Tokenizing never fails: input that cannot be interpreted
    yields `:word` tokens rather than an error, because a notepad line is
    prose until proven otherwise.

  ### Examples

      iex> {:ok, tokens} = LocalizePad.Tokenizer.tokenize("3 meters", locale: :en)
      iex> Enum.map(tokens, &{&1.kind, &1.value})
      [{:number, 3}, {:unit, "meter"}]

      iex> {:ok, tokens} = LocalizePad.Tokenizer.tokenize("2 + 2", locale: :en)
      iex> Enum.map(tokens, &{&1.kind, &1.value})
      [{:number, 2}, {:operator, :plus}, {:number, 2}]

  """
  @spec tokenize(String.t(), keyword()) :: {:ok, [Token.t()]}
  def tokenize(input, options \\ []) when is_binary(input) do
    locale = Keyword.get_lazy(options, :locale, &Localize.get_locale/0)

    # Dates and times are claimed from the raw text before the number scanner
    # runs, because a date's digits must not be broken up into arithmetic. See
    # `LocalizePad.Temporal.Scanner` for why the shape filter there is what
    # keeps `2026 + 1` a sum rather than a date.
    tokens =
      input
      |> Scanner.scan(locale: locale)
      |> Enum.flat_map(fn
        {:temporal, fields, source} -> [Token.new(:temporal, fields, source)]
        {:text, text} -> tokenize_text(text, locale)
      end)
      |> join_line_references()
      |> join_ordinals()
      |> join_percentages()
      |> join_money(locale)
      |> mark_currencies(locale)
      |> join_zones()
      |> mark_calendars()

    {:ok, tokens}
  end

  defp tokenize_text(text, locale) do
    case Localize.Number.Parser.scan(text, locale: locale) do
      elements when is_list(elements) ->
        Enum.flat_map(elements, &tokenize_element(&1, locale))

      # `scan/2` returns an error tuple for an unknown locale or oversized
      # input. Neither should take a sheet down, so the line simply produces
      # no tokens and evaluates to no answer.
      {:error, _exception} ->
        []
    end
  end

  # A line reference is written `@3` — "the answer on line 3". The number
  # scanner splits it into a stray `@` and the number, so put it back together
  # here rather than teaching the scanner about it.
  defp join_line_references([
         %Token{kind: :word, source: "@"} = at,
         %Token{kind: :number, value: line} = number | rest
       ])
       when is_integer(line) do
    # `@ 7%` is "at seven percent", not a reference to line 7. A percent sign
    # immediately after the number settles it.
    case rest do
      [%Token{kind: :operator, value: :percent} | _more] ->
        [at, number | join_line_references(rest)]

      _otherwise ->
        [Token.new(:line_ref, line, "@#{line}") | join_line_references(rest)]
    end
  end

  defp join_line_references([token | rest]), do: [token | join_line_references(rest)]
  defp join_line_references([]), do: []

  # `4th` reaches here as the number 4 and a stray `th`, because the number
  # scanner takes the digits and leaves the suffix behind. Ordinals matter for
  # recurrence phrases — `4th Thursday of November` — so put them back
  # together.
  @ordinal_suffixes ~w(st nd rd th)

  defp join_ordinals([]), do: []

  defp join_ordinals([
         %Token{kind: :number, value: value} = number,
         %Token{kind: :word, source: suffix} = word | rest
       ])
       when is_integer(value) do
    if String.downcase(suffix) in @ordinal_suffixes do
      [Token.new(:ordinal, value, "#{value}#{suffix}") | join_ordinals(rest)]
    else
      [number | join_ordinals([word | rest])]
    end
  end

  defp join_ordinals([token | rest]), do: [token | join_ordinals(rest)]

  # `20%` and `20 percent` are one value, not a number beside a symbol.
  defp join_percentages([]), do: []

  defp join_percentages([
         %Token{kind: :number, value: value},
         %Token{kind: :operator, value: :percent} | rest
       ])
       when is_number(value) do
    [Token.new(:percentage, value, "#{value}%") | join_percentages(rest)]
  end

  # `percent` is itself a CLDR unit, so it reaches here classified as `:unit`
  # rather than `:word`. Both spellings mean the same thing to a reader.
  defp join_percentages([
         %Token{kind: :number, value: value} = number,
         %Token{kind: kind, source: word} = follower | rest
       ])
       when is_number(value) and kind in [:word, :unit] do
    if String.downcase(word) in ~w(percent percentage) do
      [Token.new(:percentage, value, "#{value} #{word}") | join_percentages(rest)]
    else
      # Put both tokens back exactly as they were. Rebuilding the follower from
      # its source would lose a unit token's resolved value — `kg` would go
      # back in place of `kilogram`, and the unit would then be unknown.
      [number | join_percentages([follower | rest])]
    end
  end

  defp join_percentages([token | rest]), do: [token | join_percentages(rest)]

  # Money is only money when it is written as such — `$19`, `19 USD`,
  # `USD 19`. A bare number stays a number, which is the whole point of
  # `LocalizePad.Currency`.
  defp join_money([], _locale), do: []

  defp join_money(
         [%Token{kind: :word, source: marker}, %Token{kind: :number, value: amount} | rest],
         locale
       )
       when is_number(amount) do
    case Currency.resolve(marker, locale) do
      {:ok, code} ->
        [money_token(code, amount, "#{marker}#{amount}") | join_money(rest, locale)]

      :error ->
        [Token.new(:word, marker, marker) | join_money([number_token(amount) | rest], locale)]
    end
  end

  defp join_money(
         [%Token{kind: :number, value: amount}, %Token{kind: :word, source: marker} | rest],
         locale
       )
       when is_number(amount) do
    case Currency.resolve(marker, locale) do
      {:ok, code} ->
        [money_token(code, amount, "#{amount} #{marker}") | join_money(rest, locale)]

      :error ->
        [number_token(amount) | join_money([Token.new(:word, marker, marker) | rest], locale)]
    end
  end

  defp join_money([token | rest], locale), do: [token | join_money(rest, locale)]

  defp money_token(code, amount, source) do
    Token.new(:money, Money.new(code, to_decimal(amount)), source)
  end

  defp number_token(amount), do: Token.new(:number, amount, to_string(amount))

  # Money is decimal all the way down; going through the float would give
  # 19.999999999999996 for amounts a person typed exactly.
  defp to_decimal(amount) when is_integer(amount), do: Decimal.new(amount)
  defp to_decimal(amount) when is_float(amount), do: Decimal.from_float(amount)

  # A currency code with no amount beside it is a conversion *target*:
  # the `EUR` in `10 USD in EUR`. Runs after `join_money/2` so a code that
  # belongs to an amount has already been consumed.
  defp mark_currencies(tokens, locale) do
    Enum.map(tokens, fn
      %Token{kind: :word, source: word} = token ->
        case Currency.resolve(word, locale) do
          {:ok, code} -> Token.new(:currency, code, word)
          :error -> token
        end

      token ->
        token
    end)
  end

  # A calendar's name is only ever a conversion target, so like a zone it is
  # marked but declines to be a value on its own.
  defp mark_calendars(tokens) do
    Enum.map(tokens, fn
      %Token{kind: :word, source: word} = token ->
        case Calendars.resolve(word) do
          {:ok, calendar} -> Token.new(:calendar, calendar, word)
          :error -> token
        end

      token ->
        token
    end)
  end

  # `New York` and `Hong Kong` are two words each, so zone names are matched
  # over runs of word tokens rather than one at a time. Longest run first, so
  # `New York` wins over a hypothetical `York`.
  @maximum_zone_words 3

  defp join_zones([]), do: []

  defp join_zones([%Token{kind: :word} | _rest] = tokens) do
    case longest_zone(tokens) do
      {:ok, zone, source, consumed} ->
        [Token.new(:zone, zone, source) | tokens |> Enum.drop(consumed) |> join_zones()]

      :error ->
        [hd(tokens) | tokens |> tl() |> join_zones()]
    end
  end

  defp join_zones([token | rest]), do: [token | join_zones(rest)]

  defp longest_zone(tokens) do
    words = tokens |> Enum.take(@maximum_zone_words) |> Enum.take_while(&(&1.kind == :word))

    words
    |> Enum.count()
    |> countdown()
    |> Enum.find_value(:error, fn length ->
      source = words |> Enum.take(length) |> Enum.map_join(" ", & &1.source)

      case Zones.resolve(source) do
        {:ok, zone} -> {:ok, zone, source, length}
        :error -> nil
      end
    end)
  end

  defp countdown(0), do: []
  defp countdown(count), do: Enum.to_list(count..1//-1)

  # `scan/2` yields numbers already parsed, and everything else as text runs.
  defp tokenize_element(number, _locale) when is_number(number) do
    [Token.new(:number, number, to_string(number))]
  end

  defp tokenize_element(%Decimal{} = number, _locale) do
    [Token.new(:number, number, Decimal.to_string(number))]
  end

  defp tokenize_element(text, locale) when is_binary(text) do
    text
    |> String.split(@operator_pattern, include_captures: true, trim: true)
    |> Enum.flat_map(&split_words/1)
    |> Enum.map(&classify(&1, locale))
  end

  # An operator match is already a single piece; anything else splits on
  # whitespace into candidate words.
  defp split_words(piece) do
    if Map.has_key?(@operators, piece) or piece == "->" do
      [piece]
    else
      String.split(piece, ~r/\s+/, trim: true)
    end
  end

  # "->" is spelled as an operator but means conversion, so it is classified
  # straight to the `:to` role rather than round-tripping through the lexicon.
  defp classify("->", _locale) do
    Token.new(:keyword, :to, "->")
  end

  defp classify(word, locale) do
    case Map.fetch(@operators, word) do
      {:ok, operator} -> Token.new(:operator, operator, word)
      :error -> classify_word(word, locale)
    end
  end

  # A word may be a keyword, a unit, both, or neither. Both readings are kept
  # when they exist — `in` is the conversion keyword and also `inch`.
  defp classify_word(word, locale) do
    cond do
      SalesTax.names_tax?(word) ->
        Token.new(:tax, SalesTax.configured(), word)

      match?({:ok, _moment}, Lexicon.deictic(word, lexicon_locale(locale))) ->
        {:ok, moment} = Lexicon.deictic(word, lexicon_locale(locale))
        Token.new(:temporal, {:deictic, moment}, word)

      true ->
        classify_ordinary_word(word, locale)
    end
  end

  defp classify_ordinary_word(word, locale) do
    keyword = Lexicon.role(word, lexicon_locale(locale))
    unit = resolve_unit(word, locale)

    case {keyword, unit} do
      {{:ok, role}, {:ok, unit_name}} -> Token.new(:keyword, role, word, unit: unit_name)
      {{:ok, role}, _} -> Token.new(:keyword, role, word)
      {:error, {:ok, unit_name}} -> Token.new(:unit, unit_name, word)
      {:error, _} -> Token.new(:word, word, word)
    end
  end

  # Calendar units whose plural may be missing from Unity's alias table.
  # `month` resolves and `months` does not, while `week`/`weeks`,
  # `year`/`years` and `day`/`days` all do.
  @calendar_plurals %{
    "years" => "year",
    "months" => "month",
    "weeks" => "week",
    "days" => "day",
    "hours" => "hour",
    "minutes" => "minute",
    "seconds" => "second"
  }

  # Fills the gaps above, and *only* those.
  #
  # The first attempt at this stripped a trailing `s` from any unresolved word
  # and retried. That fixed `months` and broke more than it fixed: CLDR has a
  # `night` unit, so `hotel * 3 nights` stopped being 360 and became "360
  # nights", which then dropped out of the subtotal because a quantity will not
  # add to a number. In a language whose defining rule is that unrecognised
  # words are noise, quietly promoting English plurals to units has far too
  # wide a blast radius to take on trust.
  #
  # The missing plurals are worth fixing upstream in Unity; this table is what
  # keeps calendar arithmetic working until they are.
  defp resolve_unit(word, locale) do
    downcased = String.downcase(word)

    with {:error, _reason} <- Unity.Aliases.resolve(word),
         # Unity's table is case-sensitive, and German capitalises its nouns —
         # "Kilometer" is the identifier `kilometer` but for one letter.
         {:error, _reason} <- Unity.Aliases.resolve(downcased),
         {:error, _reason} <- calendar_plural(downcased),
         :error <- localized_unit(word, locale) do
      {:error, :unknown_unit}
    else
      {:ok, unit} -> {:ok, unit}
    end
  end

  # The CLDR display-name index is what gives a German sheet `Wochen`. It is
  # *not* consulted for English, because Unity's alias table already is the
  # English vocabulary and is deliberately narrower than CLDR: it omits
  # `nights` so that `3 nights` stays prose, and re-adding it here would undo
  # that on every English sheet.
  defp localized_unit(word, locale) do
    if language(locale) == "en", do: :error, else: Units.resolve(word, locale)
  end

  defp language(locale) do
    case Localize.validate_locale(locale) do
      {:ok, tag} -> to_string(tag.language)
      _other -> "en"
    end
  end

  defp calendar_plural(word) do
    case Map.fetch(@calendar_plurals, word) do
      {:ok, singular} -> Unity.Aliases.resolve(singular)
      :error -> {:error, :unknown_unit}
    end
  end

  # The lexicon is keyed by language, and `Localize` is deliberately permissive
  # about locales it holds no data for — a request for `pt-BR` resolves to a
  # tag whose `:cldr_locale_id` is a locale we do have. Follow that resolution
  # so the operator vocabulary matches the data the rest of the line uses.
  defp lexicon_locale(locale) do
    case Localize.validate_locale(locale) do
      {:ok, %{cldr_locale_id: cldr_locale_id}} -> cldr_locale_id
      _other -> :en
    end
  end
end
