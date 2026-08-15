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

  alias LocalizePad.{Lexicon, Token}
  alias LocalizePad.Temporal.Scanner

  # Multi-character operators must be tried before their single-character
  # prefixes, hence "->" and "**" first. The `u` modifier is required: without
  # it the character class matches bytes, and `×` (two UTF-8 bytes) is torn in
  # half rather than recognised.
  @operator_pattern ~r/(->|\*\*|[+\-*\/^()=,;×÷])/u

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
    ";" => :semicolon
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
         %Token{kind: :word, source: "@"},
         %Token{kind: :number, value: line} | rest
       ])
       when is_integer(line) do
    [Token.new(:line_ref, line, "@#{line}") | join_line_references(rest)]
  end

  defp join_line_references([token | rest]), do: [token | join_line_references(rest)]
  defp join_line_references([]), do: []

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
    keyword = Lexicon.role(word, lexicon_locale(locale))
    unit = resolve_unit(word)

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
  defp resolve_unit(word) do
    case Unity.Aliases.resolve(word) do
      {:ok, unit} ->
        {:ok, unit}

      {:error, _reason} = error ->
        case Map.fetch(@calendar_plurals, String.downcase(word)) do
          {:ok, singular} -> Unity.Aliases.resolve(singular)
          :error -> error
        end
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
