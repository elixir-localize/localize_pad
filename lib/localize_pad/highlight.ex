defmodule LocalizePad.Highlight do
  @moduledoc """
  Breaking a line into coloured segments, for an editor to draw.

  ## Highlighting is the engine's opinion, not a second one

  A syntax highlighter is usually its own little parser, and it drifts: the
  editor colours `in` as a keyword while the evaluator reads it as inches, and
  the reader believes the colour. That is worse than no colour at all, because
  a wrong highlight is indistinguishable from a right one until the answer
  disagrees.

  So there is no second parser here. Segments come from the same tokens the
  sheet was evaluated from, placed by the spans `LocalizePad.Tokenizer` records.
  If the engine changes its mind about a word, the colour changes with it.

  The fidelity is to the *tokenizer*, which is one stage short of the whole
  truth. `a` in "just a thought" is coloured as a keyword because that is what
  it is — CLDR's abbreviation for `year` — and the parser then discards it as
  prose, having found nothing for it to bind to. The colour is a shade keener
  than the reading. That is the honest limit of colouring without evaluating,
  and it errs in the direction of showing what the engine *considered*, never
  of inventing a reading the engine never had.

  ## The whole line is covered

  Every byte of the line lands in exactly one segment, gaps included — the
  spaces between tokens come back as segments with no class. An editor drawing
  these in order reproduces the line exactly, which is what lets the result be
  laid *behind* a transparent textarea without a character drifting out of
  place.

  ## What is coloured

  Token kinds, plus three things the tokenizer never sees because
  `LocalizePad.Line` strips them first: the `#` heading, the `//` comment, and
  the `Label:` prefix. Those are classified here rather than tokenized, which
  is why a comment's contents are never coloured as arithmetic — it is text the
  engine deliberately ignored, and colouring it would claim otherwise.

  """

  alias LocalizePad.{Line, Token, Tokenizer}

  @type segment :: {atom() | nil, String.t()}

  @trailing_comment ~r{//.*$}u

  @doc """
  Breaks a line of source into segments.

  ### Arguments

  * `source` - one line of the sheet, exactly as typed.

  * `options` - a keyword list of options.

  ### Options

  * `:locale` - the locale to read the line in, which decides what is a number
    and what is a unit. Defaults to `Localize.get_locale/0`.

  * `:variables` - the names bound above this line. A word matching one is
    coloured as a variable, which is the only way to see at a glance that a
    name was recognised rather than skipped as prose. Defaults to `[]`.

  ### Returns

  * A list of `{class, text}` segments whose texts concatenate to `source`.
    `class` is a token kind, one of `:heading`, `:comment` or `:label`, or
    `nil` for text that carries no colour.

  ### Examples

      iex> LocalizePad.Highlight.line("19 + 22", locale: :en)
      [{:number, "19"}, {nil, " "}, {:operator, "+"}, {nil, " "}, {:number, "22"}]

      iex> LocalizePad.Highlight.line("# Trip", locale: :en)
      [{:heading, "# Trip"}]

  """
  @spec line(String.t(), keyword()) :: [segment()]
  def line(source, options \\ []) when is_binary(source) do
    locale = Keyword.get_lazy(options, :locale, &Localize.get_locale/0)
    variables = options |> Keyword.get(:variables, []) |> MapSet.new()

    0
    |> Line.classify(source, locale)
    |> segments(source, locale, variables)
    |> Enum.reject(fn {_class, text} -> text == "" end)
  end

  @doc """
  Breaks every line of a sheet into segments.

  ### Arguments

  * `source` - the sheet's text.

  * `options` - a keyword list of options, as `line/2`.

  ### Returns

  * A list of segment lists, one per line, in order.

  ### Examples

      iex> LocalizePad.Highlight.lines("# Trip\\n19 + 22", locale: :en) |> length()
      2

  """
  @spec lines(String.t(), keyword()) :: [[segment()]]
  def lines(source, options \\ []) when is_binary(source) do
    {segments, _bound} =
      source
      |> String.split("\n")
      |> Enum.map_reduce(MapSet.new(), fn source, bound ->
        segments = line(source, Keyword.put(options, :variables, bound))

        {segments, bind(source, bound)}
      end)

    segments
  end

  # Declare-before-use, so a name colours from the line below the one that
  # bound it. Reading the declaration off the line itself keeps this
  # independent of whether the sheet evaluated.
  defp bind(source, bound) do
    case Line.classify(0, source) do
      %Line{kind: :declaration, name: name} -> MapSet.put(bound, name)
      _other -> bound
    end
  end

  # A heading and a comment are whole-line decisions, and neither is tokenized
  # at all — colouring a comment's contents as arithmetic would claim the
  # engine read something it deliberately skipped.
  defp segments(%Line{kind: :heading}, source, _locale, _variables), do: [{:heading, source}]
  defp segments(%Line{kind: :comment}, source, _locale, _variables), do: [{:comment, source}]
  defp segments(%Line{kind: :blank}, source, _locale, _variables), do: [{nil, source}]

  defp segments(%Line{expression: nil}, source, _locale, _variables), do: [{nil, source}]

  defp segments(%Line{expression: expression} = line, source, locale, variables) do
    {body, comment} = split_comment(source)

    case :binary.match(body, expression) do
      {start, length} ->
        prefix(line, binary_part(body, 0, start)) ++
          tokenized(expression, locale, variables) ++
          [{nil, binary_part(body, start + length, byte_size(body) - start - length)}] ++
          comment

      # The expression was rewritten rather than sliced out — nothing to align
      # against, so the line is left plain rather than coloured by guesswork.
      :nomatch ->
        [{nil, body} | comment]
    end
  end

  # Whatever precedes the expression is the label, the name of a declaration,
  # or leading space.
  defp prefix(_line, ""), do: []
  defp prefix(%Line{label: nil, name: nil}, text), do: [{nil, text}]
  defp prefix(_line, text), do: [{:label, text}]

  defp split_comment(source) do
    case Regex.run(@trailing_comment, source, return: :index) do
      [{start, length}] ->
        {binary_part(source, 0, start), [{:comment, binary_part(source, start, length)}]}

      nil ->
        {source, []}
    end
  end

  # The gaps matter as much as the tokens: an editor drawing these in order has
  # to reproduce the line byte for byte, or the text drifts out from under the
  # cursor.
  defp tokenized(expression, locale, variables) do
    {:ok, tokens} = Tokenizer.tokenize(expression, locale: locale)

    {segments, cursor} =
      tokens
      |> Enum.filter(&placed?/1)
      |> classify(variables)
      |> Enum.reduce({[], 0}, fn {token, class}, {segments, cursor} ->
        gap = {nil, binary_part(expression, cursor, token.start - cursor)}
        coloured = {class, binary_part(expression, token.start, token.length)}

        {[coloured, gap | segments], token.start + token.length}
      end)

    tail = {nil, binary_part(expression, cursor, byte_size(expression) - cursor)}

    Enum.reverse([tail | segments])
  end

  # A bare word is a variable reference when the sheet has bound that name, and
  # prose otherwise. It is the one colour that says "this word did something".
  #
  # Names are phrases — `monthly rent` is one variable and two word tokens — so
  # runs are matched longest-first, exactly as `LocalizePad.Parser` does. Asking
  # the question a different way here is how a highlighter starts disagreeing
  # with the engine it is supposed to be reporting on.
  defp classify([], _variables), do: []

  defp classify([%Token{kind: :word} | _rest] = tokens, variables) do
    case longest_name(tokens, variables) do
      {:ok, count} ->
        Enum.map(Enum.take(tokens, count), &{&1, :variable}) ++
          classify(Enum.drop(tokens, count), variables)

      :error ->
        [{hd(tokens), :word} | classify(tl(tokens), variables)]
    end
  end

  defp classify([token | rest], variables) do
    [{token, token.kind} | classify(rest, variables)]
  end

  defp longest_name(tokens, variables) do
    words = Enum.take_while(tokens, &(&1.kind == :word))

    words
    |> Enum.count()
    |> countdown()
    |> Enum.find_value(:error, fn length ->
      name = words |> Enum.take(length) |> Enum.map_join(" ", & &1.source)

      if MapSet.member?(variables, name), do: {:ok, length}
    end)
  end

  defp countdown(0), do: []
  defp countdown(count), do: Enum.to_list(count..1//-1)

  # A token whose span overlaps the one before it would make the gap negative
  # and the line unreproducible. None should, but a highlighter that corrupts
  # the text under the cursor is a worse failure than one that skips a colour.
  defp placed?(%Token{start: start, length: length}) do
    is_integer(start) and is_integer(length)
  end
end
