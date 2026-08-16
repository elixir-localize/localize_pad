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

  Every token records where in the line it was read from, which is what editor
  decoration needs — highlighting, hover-to-peek, click-an-answer-to-reference
  all start from mapping a character position back to the token covering it.

  A number's source *text* is genuinely unrecoverable from `scan/2`, because
  `"02"` and `"2"` both arrive as `2`. Its *span* is not: the text runs come
  back verbatim, so locating the next one leaves a gap, and the gap is exactly
  the number that was consumed there. `"02"` therefore ends up with a token
  whose value is `2` and whose span is two bytes wide — which is what an editor
  wants, and what reconstructing the text from the value would have got wrong.

  A token built from several — `@` and `3` into a line reference — covers what
  all of them covered. A token whose source was rewritten rather than sliced is
  left unplaced rather than guessed at; an editor can skip what it cannot
  locate, but it cannot un-highlight a wrong guess.

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
      |> place_chunks(locale)
      |> join_line_references()
      |> join_ordinals()
      |> join_percentages()
      |> join_money(locale)
      |> mark_currencies(locale)
      |> join_zones()
      |> mark_calendars()
      |> mark_preferences(locale)

    {:ok, tokens}
  end

  # The chunks concatenate to the input, so a running cursor is enough to know
  # where each one starts.
  defp place_chunks(chunks, locale) do
    {tokens, _cursor} =
      Enum.flat_map_reduce(chunks, 0, fn
        {:temporal, fields, source}, cursor ->
          token = :temporal |> Token.new(fields, source) |> Token.at(cursor, byte_size(source))

          {[token], cursor + byte_size(source)}

        {:text, text}, cursor ->
          {tokenize_text(text, locale, cursor), cursor + byte_size(text)}
      end)

    tokens
  end

  defp tokenize_text(text, locale, offset) do
    case Localize.Number.Parser.scan(text, locale: locale) do
      elements when is_list(elements) ->
        elements
        |> element_spans(text)
        |> Enum.flat_map(&tokenize_span(&1, text, locale, offset))

      # `scan/2` returns an error tuple for an unknown locale or oversized
      # input. Neither should take a sheet down, so the line simply produces
      # no tokens and evaluates to no answer.
      {:error, _exception} ->
        []
    end
  end

  # `scan/2` hands back numbers already parsed, which loses their text — `"02"`
  # and `"2"` both arrive as `2`. The *spans* survive, though: the text runs
  # come back verbatim, so each one can be located exactly, and a number is
  # whatever sits in the gap before the next of them.
  #
  # Numbers *can* arrive adjacent, which an earlier version of this asserted
  # they could not: `2026-07-03` scans as `[2026, -7, -3]`, the hyphens read as
  # signs rather than separators. Two numbers sharing one gap cannot be told
  # apart — nothing here knows where `-07` ends and `-03` begins — so they are
  # left unplaced rather than guessed at, on the same principle as everything
  # else here: an editor can skip what it cannot locate, but it cannot
  # un-highlight a wrong guess.
  defp element_spans(elements, text, cursor \\ 0)

  defp element_spans([], _text, _cursor), do: []

  defp element_spans([element | rest], text, cursor) when is_binary(element) do
    case locate(text, element, cursor) do
      {:ok, start, length} ->
        [{element, start, length} | element_spans(rest, text, start + length)]

      :error ->
        [{element, nil, nil} | element_spans(rest, text, cursor)]
    end
  end

  defp element_spans(elements, text, cursor) do
    {numbers, rest} = Enum.split_while(elements, &(not is_binary(&1)))
    finish = next_text_start(rest, text, cursor)

    case numbers do
      [only] -> [{only, cursor, finish - cursor} | element_spans(rest, text, finish)]
      several -> Enum.map(several, &{&1, nil, nil}) ++ element_spans(rest, text, finish)
    end
  end

  defp next_text_start([following | _rest], text, cursor) when is_binary(following) do
    case locate(text, following, cursor) do
      {:ok, start, _length} -> start
      :error -> byte_size(text)
    end
  end

  defp next_text_start(_none, text, _cursor), do: byte_size(text)

  defp locate(text, fragment, cursor) when cursor <= byte_size(text) do
    case :binary.match(text, fragment, scope: {cursor, byte_size(text) - cursor}) do
      {start, length} -> {:ok, start, length}
      :nomatch -> :error
    end
  end

  defp locate(_text, _fragment, _cursor), do: :error

  defp tokenize_span({element, nil, _length}, _text, locale, _offset) do
    tokenize_element(element, locale)
  end

  defp tokenize_span({element, start, length}, text, locale, offset) do
    element
    |> tokenize_element(locale)
    |> place_in(slice(text, start, length), offset + start, not is_binary(element))
  end

  # Belt and braces. Every span above is computed from `text` itself, but this
  # sits on the render path and a slice that ran off the end would raise rather
  # than lose a colour.
  defp slice(text, start, length) do
    available = max(byte_size(text) - start, 0)

    binary_part(text, min(start, byte_size(text)), min(max(length, 0), available))
  end

  # Every token a text run produces carries a verbatim slice of it, and they
  # come out in order, so locating each in turn from a running cursor places
  # them all. A number produces one token, which covers the whole span
  # including any leading zero its value no longer records.
  defp place_in(tokens, source, offset, number?)

  defp place_in([token], source, offset, true) do
    [Token.at(token, offset, byte_size(source))]
  end

  defp place_in(tokens, source, offset, _number?) do
    {placed, _cursor} =
      Enum.map_reduce(tokens, 0, fn token, cursor ->
        remaining = byte_size(source) - cursor

        case :binary.match(source, token.source, scope: {cursor, remaining}) do
          {start, length} ->
            {Token.at(token, offset + start, length), start + length}

          # A token whose source was rewritten rather than sliced — the `->`
          # spelling of `to`, say. Leaving it unplaced is right: an editor can
          # skip what it cannot locate, but it cannot un-highlight a guess.
          :nomatch ->
            {token, cursor}
        end
      end)

    placed
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
        reference = Token.covering(Token.new(:line_ref, line, "@#{line}"), [at, number])

        [reference | join_line_references(rest)]
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
      ordinal = Token.covering(Token.new(:ordinal, value, "#{value}#{suffix}"), [number, word])

      [ordinal | join_ordinals(rest)]
    else
      [number | join_ordinals([word | rest])]
    end
  end

  defp join_ordinals([token | rest]), do: [token | join_ordinals(rest)]

  # `20%` and `20 percent` are one value, not a number beside a symbol.
  defp join_percentages([]), do: []

  defp join_percentages([
         %Token{kind: :number, value: value} = number,
         %Token{kind: :operator, value: :percent} = sign | rest
       ])
       when is_number(value) do
    percentage = Token.covering(Token.new(:percentage, value, "#{value}%"), [number, sign])

    [percentage | join_percentages(rest)]
  end

  # `percent` is itself a CLDR unit, so it reaches here classified as `:unit`
  # rather than `:word`. Both spellings mean the same thing to a reader.
  defp join_percentages([
         %Token{kind: :number, value: value} = number,
         %Token{kind: kind, source: word} = follower | rest
       ])
       when is_number(value) and kind in [:word, :unit] do
    if String.downcase(word) in ~w(percent percentage) do
      spelled = Token.new(:percentage, value, "#{value} #{word}")

      [Token.covering(spelled, [number, follower]) | join_percentages(rest)]
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
         [
           %Token{kind: :word, source: marker} = symbol,
           %Token{kind: :number, value: amount} = number | rest
         ],
         locale
       )
       when is_number(amount) do
    case Currency.resolve(marker, locale) do
      {:ok, code} ->
        money = money_token(code, amount, "#{marker}#{amount}")

        [Token.covering(money, [symbol, number]) | join_money(rest, locale)]

      :error ->
        [symbol | join_money([number | rest], locale)]
    end
  end

  defp join_money(
         [
           %Token{kind: :number, value: amount} = number,
           %Token{kind: :word, source: marker} = code_word | rest
         ],
         locale
       )
       when is_number(amount) do
    case Currency.resolve(marker, locale) do
      {:ok, code} ->
        money = money_token(code, amount, "#{amount} #{marker}")

        [Token.covering(money, [number, code_word]) | join_money(rest, locale)]

      :error ->
        [number | join_money([code_word | rest], locale)]
    end
  end

  defp join_money([token | rest], locale), do: [token | join_money(rest, locale)]

  defp money_token(code, amount, source) do
    Token.new(:money, Money.new(code, to_decimal(amount)), source)
  end

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
          {:ok, code} -> Token.covering(Token.new(:currency, code, word), [token])
          :error -> token
        end

      token ->
        token
    end)
  end

  # `42 km in local units`. Like a calendar, this only ever names a conversion
  # target, and it carries the locale it was read under: "local" means the
  # locale the sheet is being read in, and the sheet is re-tokenized whenever
  # that changes, so resolving it here rather than at evaluation keeps the
  # answer and the question in step.
  #
  # Runs last, after currencies and calendars, so a word that is genuinely one
  # of those keeps its stronger reading. `local` is not a unit in any locale's
  # vocabulary, but the ordering costs nothing and the alternative is a rule
  # nobody can see.
  defp mark_preferences(tokens, locale) do
    Enum.map(tokens, fn
      %Token{kind: :word, source: word} = token ->
        if Lexicon.preference?(word, lexicon_locale(locale)) do
          Token.covering(Token.new(:preference, locale, word), [token])
        else
          token
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
          {:ok, calendar} -> Token.covering(Token.new(:calendar, calendar, word), [token])
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
        token = Token.covering(Token.new(:zone, zone, source), Enum.take(tokens, consumed))

        [token | tokens |> Enum.drop(consumed) |> join_zones()]

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
    |> Enum.flat_map(&split_words(&1, locale))
    |> Enum.map(&classify(&1, locale))
  end

  # Languages written without word spaces. Splitting on whitespace yields one
  # enormous token, so these are segmented against the locale's own vocabulary
  # instead.
  @unspaced ~w(ja zh th ko lo km my)

  # An operator match is already a single piece; anything else splits on
  # whitespace into candidate words.
  defp split_words(piece, locale) do
    cond do
      Map.has_key?(@operators, piece) or piece == "->" ->
        [piece]

      language(locale) in @unspaced ->
        piece |> String.split(~r/\s+/, trim: true) |> Enum.flat_map(&segment(&1, locale))

      true ->
        String.split(piece, ~r/\s+/, trim: true)
    end
  end

  # Segmentation for a script written without word spaces.
  #
  # The first attempt here was a greedy longest-match against the vocabulary
  # this program happens to know. It worked for `100キロメートルをマイルで` and
  # was wrong in principle: a word the program had never heard of would be
  # shattered a character at a time, and `Japanese` became eight single letters
  # of which `J` is joule in Unity's abbreviation table.
  #
  # `Unicode.String.split/2` is the real thing — UAX #29 word breaking, with
  # ICU's dictionaries for the scripts that need them. It finds *actual* words
  # rather than familiar ones, so an unrecognised Japanese word becomes one
  # noise token instead of a handful of accidental units, and mixed-script text
  # keeps each run's own boundaries without anything here knowing which script
  # is which.
  defp segment(text, locale) do
    case Unicode.String.split(text, break: :word, locale: language(locale), trim: true) do
      pieces when is_list(pieces) ->
        pieces

      # The dictionaries are downloaded rather than vendored, so a checkout
      # that has not run `mix unicode.string.download.dictionaries` gets an
      # error here. Falling back to the whole run keeps the line readable as
      # prose rather than failing it.
      _unavailable ->
        [text]
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
        Token.new(:tax, SalesTax.named(word), word)

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

  # Unity 1.1 derives plurals from the CLDR unit list, so `months`, `weeks` and
  # the rest resolve on their own. The table of hand-listed calendar plurals
  # that used to sit here is gone with them.
  defp resolve_unit(word, locale) do
    downcased = String.downcase(word)

    with {:error, _reason} <- Unity.Aliases.resolve(word),
         # Unity's table is case-sensitive, and German capitalises its nouns —
         # "Kilometer" is the identifier `kilometer` but for one letter.
         {:error, _reason} <- Unity.Aliases.resolve(downcased),
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

  # A sheet arrives holding a resolved tag, so the common case is a field read.
  # Both of these are called per word, and re-validating a tag that is already
  # a tag put a CLDR lookup in the middle of the tokenizer's inner loop.
  defp language(%Localize.LanguageTag{language: language}), do: to_string(language)

  defp language(locale) do
    case Localize.validate_locale(locale) do
      {:ok, tag} -> to_string(tag.language)
      _other -> "en"
    end
  end

  # The lexicon is keyed by language, and `Localize` is deliberately permissive
  # about locales it holds no data for — a request for `pt-BR` resolves to a
  # tag whose `:cldr_locale_id` is a locale we do have. Follow that resolution
  # so the operator vocabulary matches the data the rest of the line uses.
  defp lexicon_locale(%Localize.LanguageTag{} = tag), do: tag

  defp lexicon_locale(locale) do
    case Localize.validate_locale(locale) do
      {:ok, tag} -> tag
      _other -> :en
    end
  end
end
