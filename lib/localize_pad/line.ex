defmodule LocalizePad.Line do
  @moduledoc """
  One line of a sheet: its source text, what kind of line it is, and — once
  the sheet has been evaluated — its answer.

  ## Line kinds

  * `:blank` — nothing but whitespace.

  * `:heading` — begins with `#`. Shows no answer, and bounds the range a
    subtotal reaches back over.

  * `:comment` — begins with `//`.

  * `:aggregate` — `sum`, `average`, `median`, `count`, `min` or `max`, alone
    on a line. Summarises every entry above it, back to the previous aggregate
    or heading.

  * `:declaration` — `name = expression`. Binds a name for the lines below.

  * `:trip`, `:trip_stop`, `:trip_end` — the lines of an itinerary. See
    `LocalizePad.Trip`.

  * `:expression` — everything else, including a line carrying a label.

  ## Aggregates are typed, not clicked

  In Soulver a subtotal is made by a keystroke on an empty line, and the sheet
  file records it out of band. A sheet here is plain text first — it has to
  survive being copied into a chat window and pasted back — so the aggregate
  is a word you can type. `sum` on its own line is the marker, and `average`,
  `mean`, `median`, `count`, `min` and `max` are the others.

  Which words those are is the reader's business, not English's:
  `Durchschnitt` on a German sheet is the same line as `average` on an English
  one. `LocalizePad.Lexicon.aggregate/2` holds the vocabulary.

  ## Labels

  `Cost of the iPhone: $999` evaluates to 999; the label is stripped before
  parsing so its digits cannot leak into the arithmetic. A colon must be
  followed by whitespace to count as a label, which is what keeps a clock time
  like `14:45` from being read as a label named "14".

  """

  alias LocalizePad.{
    Evaluator,
    Lexicon,
    Locales,
    Parser,
    Telemetry,
    Token,
    Tokenizer,
    Trip,
    Value
  }

  @type kind ::
          :blank
          | :heading
          | :comment
          | :aggregate
          | :declaration
          | :expression
          | :trip
          | :trip_stop
          | :trip_end

  @type t :: %__MODULE__{
          index: non_neg_integer(),
          source: String.t(),
          kind: kind(),
          label: String.t() | nil,
          name: String.t() | nil,
          aggregate: Lexicon.aggregate() | nil,
          expression: String.t() | nil,
          tags: [String.t()],
          value: Evaluator.value() | nil,
          formatted: String.t() | nil,
          error: term() | nil,
          depends_on: MapSet.t(non_neg_integer())
        }

  defstruct [
    :index,
    :source,
    :kind,
    :label,
    :name,
    :aggregate,
    :expression,
    :value,
    :formatted,
    :error,
    tags: [],
    depends_on: MapSet.new()
  ]

  # A trailing `// ...` comment is stripped from every line before anything
  # else looks at it.
  @trailing_comment ~r{//.*$}u

  @heading ~r/^\s*#/u
  @comment ~r{^\s*//}u

  # A tag is `#` and a word, anywhere but the start of a line — where a `#` is
  # a heading, and stays one. Letters rather than `\w` so `#comida` and `#食費`
  # tag a sheet as readily as `#food`.
  #
  # Tags are lifted out before anything else reads the line, which is what lets
  # `Calamari: 18 #ann` keep its label and its arithmetic, and `sum #ann` still
  # look like the word `sum` to the aggregate table.
  @tag ~r/(?<=\s)#(\p{L}[\p{L}\p{N}_-]*)/u

  # A name is a word or phrase: starts with a letter, then letters, digits,
  # spaces and underscores. Requiring a letter first keeps `2 + 2 = 4` from
  # being read as a declaration.
  @declaration ~r/^\s*(\p{L}[\p{L}\p{N}_ ]*?)\s*=\s*(.+)$/u

  # The label runs to the first colon, and the colon must be followed by
  # whitespace. At least one letter is required so that `14:45 ` is a time
  # rather than a label.
  @label ~r/^\s*([^:\n]*\p{L}[^:\n]*):\s+(.*)$/u

  @doc """
  Classifies a line of source text.

  Classification is purely syntactic — it does not evaluate anything. The
  resulting line has its `:kind`, and where applicable the `:label`, `:name`,
  `:aggregate` and `:expression` it was split into.

  ### Arguments

  * `index` - the zero-based position of the line in the sheet.

  * `source` - the line's text.

  ### Returns

  * A `t:LocalizePad.Line.t/0` with no value yet.

  ### Examples

      iex> LocalizePad.Line.classify(0, "# Trip costs").kind
      :heading

      iex> line = LocalizePad.Line.classify(0, "cost = 550")
      iex> {line.kind, line.name, line.expression}
      {:declaration, "cost", "550"}

      iex> line = LocalizePad.Line.classify(0, "Breakfast: 19 + 22")
      iex> {line.kind, line.label, line.expression}
      {:expression, "Breakfast", "19 + 22"}

      iex> line = LocalizePad.Line.classify(0, "median")
      iex> {line.kind, line.aggregate}
      {:aggregate, :median}

  """
  @spec classify(non_neg_integer(), String.t(), Locales.locale()) :: t()
  def classify(index, source, locale \\ :en) when is_integer(index) and is_binary(source) do
    line = %__MODULE__{index: index, source: source}
    stripped = source |> String.replace(@trailing_comment, "") |> String.trim()
    {tags, body} = extract_tags(stripped)

    # Three kinds are decided by the whole line, before anything looks at what
    # it says — and two of them carry no tags, because a `#` that opens a line
    # is a heading and a `#` inside a comment is part of the comment.
    cond do
      Regex.match?(@comment, source) -> %{line | kind: :comment}
      Regex.match?(@heading, source) -> %{line | kind: :heading}
      body == "" -> %{line | kind: :blank, tags: tags}
      true -> classify_body(%{line | tags: tags}, body, locale)
    end
  end

  # The rest are decided by the shape of what is left, most particular first: a
  # word that names a function, then the lines of a trip, then a declaration,
  # then a label. Anything that is none of those is an expression, which is
  # most lines.
  defp classify_body(line, body, locale) do
    cond do
      function = aggregate_function(body, locale) ->
        %{line | kind: :aggregate, aggregate: function}

      kind = trip_kind(body, locale) ->
        %{line | kind: kind, expression: body}

      captures = Regex.run(@declaration, body) ->
        [_whole, name, expression] = captures
        %{line | kind: :declaration, name: normalize_name(name), expression: expression}

      captures = Regex.run(@label, body) ->
        [_whole, label, expression] = captures
        %{line | kind: :expression, label: String.trim(label), expression: expression}

      true ->
        %{line | kind: :expression, expression: body}
    end
  end

  @doc """
  The pattern that finds a tag in a line.

  Exposed so `LocalizePad.Highlight` can colour tags without keeping a second
  copy of the rule. One regex, one definition of what a tag is — the editor
  cannot come to disagree with the engine about which words are tags.

  ### Returns

  * A `t:Regex.t/0` whose whole match is the tag as written, `#` included, and
    whose one capture is the name.

  ### Examples

      iex> Regex.run(LocalizePad.Line.tag_pattern(), " 18 #food")
      ["#food", "food"]

  """
  @spec tag_pattern() :: Regex.t()
  def tag_pattern, do: @tag

  @doc """
  Evaluates a classified line against the sheet's current state.

  ### Arguments

  * `line` - a line from `classify/2`.

  * `context` - a map with `:variables` (name to value), `:answers` (line
    index to value) and `:locale`.

  ### Returns

  * The line with `:value`, `:formatted`, `:error` and `:depends_on` filled
    in. A line that cannot be evaluated carries an `:error` and no value; it
    never raises.

  """
  @spec evaluate(t(), map()) :: t()
  def evaluate(%__MODULE__{kind: kind} = line, _context)
      when kind in [:blank, :heading, :comment] do
    line
  end

  def evaluate(%__MODULE__{kind: :aggregate} = line, _context) do
    # Aggregates are filled in by the sheet, which is the only thing that knows
    # what range they cover.
    line
  end

  def evaluate(%__MODULE__{kind: kind} = line, _context)
      when kind in [:trip, :trip_stop, :trip_end] do
    # So are the lines of a trip, for the same reason: a stop's dates depend on
    # every stop above it, and the sheet is what holds them.
    line
  end

  def evaluate(%__MODULE__{expression: expression} = line, context) do
    locale = Map.fetch!(context, :locale)
    variables = Map.fetch!(context, :variables)

    case attempt(expression, context) do
      {:ok, value, ast} ->
        %{
          line
          | value: value,
            formatted: format(value, locale, prefer_local(context, ast)),
            error: nil
        }
        |> put_dependencies(ast, variables, context)

      {:error, reason} ->
        %{line | value: nil, formatted: nil, error: reason}
        |> put_dependencies(nil, variables, context)
    end
  end

  # Errors that say the units disagreed, rather than that the line was
  # malformed. Only these are worth a second reading — a missing operand will
  # still be missing however the words are read.
  @disagreements [:incompatible, :unsupported_operation]

  # `19 + 22 in cash` parses as twenty-two inches, because that is what `in`
  # after a number usually means and the parser has nothing else to go on. It
  # is only when inches meet a dimensionless number that the reading is
  # revealed as wrong, at which point the ambiguous words are stripped of their
  # unit readings and the line is read again as prose.
  #
  # The retry is skipped when there was nothing ambiguous to demote, so an
  # honest type error is reported once and not chased.
  defp attempt(expression, context) do
    locale = Map.fetch!(context, :locale)

    with {:ok, tokens} <- Tokenizer.tokenize(expression, locale: locale) do
      case compute(tokens, context) do
        {:error, reason} when elem(reason, 0) in @disagreements ->
          tokens |> retry(context, reason) |> report(tokens, locale)

        result ->
          report(result, tokens, locale)
      end
    end
  end

  # A refused line is the only signal there is about which phrasings people
  # expect to work, so it is reported — as a shape, never as text. See
  # `LocalizePad.Telemetry`, which is where the promise not to record anyone's
  # sheet is actually kept.
  defp report({:error, reason}, tokens, locale) do
    Telemetry.refused(reason, tokens, locale)

    {:error, reason}
  end

  defp report(result, _tokens, _locale), do: result

  defp retry(tokens, context, reason) do
    demoted = Enum.map(tokens, &Token.demote/1)

    if demoted == tokens do
      {:error, reason}
    else
      case compute(demoted, context) do
        {:ok, value, ast} -> {:ok, value, ast}
        {:error, _second_reason} -> {:error, reason}
      end
    end
  end

  defp compute(tokens, context) do
    locale = Map.fetch!(context, :locale)
    variables = Map.fetch!(context, :variables)
    answers = Map.fetch!(context, :answers)

    options = [variables: Map.keys(variables), locale: locale, zone: Map.get(context, :zone)]

    with {:ok, ast} <- Parser.parse(tokens, options),
         {:ok, resolved} <- resolve_line_references(ast, answers),
         {:ok, value} <- Evaluator.eval(resolved, variables) do
      {:ok, value, ast}
    end
  end

  defp format(value, locale, prefer_local) do
    case Value.format(value, locale: locale, prefer_local: prefer_local) do
      {:ok, formatted} -> formatted
      {:error, _reason} -> nil
    end
  end

  # The always-in-my-units setting yields to a line that named its own unit.
  # `3 meters to feet` asked for feet, and answering in metres because the
  # reader is Australian would override the question with a preference — which
  # is the opposite of what the setting is for.
  #
  # Only the outermost conversion counts. A unit named deeper in an expression
  # is an operand rather than the answer's unit, and `(3 m to ft) + 1 ft` is a
  # sum whose unit the reader never stated.
  defp prefer_local(context, ast) do
    Map.get(context, :prefer_local, false) and not match?({:convert, _left, _right}, ast)
  end

  # A line reference is resolved against answers already computed. References
  # only ever point upward, so by the time this runs the answer either exists
  # or the reference is dangling.
  defp resolve_line_references({:line_ref, line_number}, answers) do
    case Map.fetch(answers, line_number - 1) do
      {:ok, value} -> {:ok, {:number, value}}
      :error -> {:error, {:dangling_line_reference, line_number}}
    end
  end

  defp resolve_line_references({:binary, operator, left, right}, answers) do
    with {:ok, left} <- resolve_line_references(left, answers),
         {:ok, right} <- resolve_line_references(right, answers) do
      {:ok, {:binary, operator, left, right}}
    end
  end

  defp resolve_line_references({:convert, expression, target}, answers) do
    with {:ok, expression} <- resolve_line_references(expression, answers),
         {:ok, target} <- resolve_line_references(target, answers) do
      {:ok, {:convert, expression, target}}
    end
  end

  defp resolve_line_references({:neg, expression}, answers) do
    with {:ok, expression} <- resolve_line_references(expression, answers) do
      {:ok, {:neg, expression}}
    end
  end

  defp resolve_line_references(node, _answers), do: {:ok, node}

  # The graph records which *lines* a line depends on, whether the dependency
  # was written as `@3` or as a variable that line 3 declared. Both are edges;
  # the difference is only in how the user wrote it.
  defp put_dependencies(line, nil, _variables, _context) do
    %{line | depends_on: MapSet.new()}
  end

  defp put_dependencies(line, ast, _variables, context) do
    declared_at = Map.fetch!(context, :declared_at)

    dependencies =
      ast
      |> references()
      |> Enum.reduce(MapSet.new(), fn
        {:line_ref, line_number}, accumulated ->
          MapSet.put(accumulated, line_number - 1)

        {:variable, name}, accumulated ->
          case Map.fetch(declared_at, name) do
            {:ok, index} -> MapSet.put(accumulated, index)
            :error -> accumulated
          end
      end)

    %{line | depends_on: dependencies}
  end

  defp references({:binary, _operator, left, right}) do
    references(left) ++ references(right)
  end

  defp references({:convert, expression, target}) do
    references(expression) ++ references(target)
  end

  defp references({:neg, expression}), do: references(expression)
  defp references({:line_ref, _line} = node), do: [node]
  defp references({:variable, _name} = node), do: [node]
  defp references(_node), do: []

  # Every tag on the line, lowercased so `#Ann` and `#ann` are one tag, and the
  # line with them taken out. Order is kept and duplicates are not, because a
  # tag written twice is still one tag.
  defp extract_tags(body) do
    tags =
      @tag
      |> Regex.scan(" " <> body)
      |> Enum.map(fn [_whole, name] -> String.downcase(name) end)
      |> Enum.uniq()

    {tags, (" " <> body) |> String.replace(@tag, "") |> String.trim()}
  end

  # `nil` rather than `:error`, for the same reason as the aggregate below it:
  # the `cond` binds the kind and tests it in one clause.
  defp trip_kind(body, locale) do
    case Trip.classify(body, locale) do
      {:ok, kind} -> kind
      :error -> nil
    end
  end

  # `nil` rather than `:error`, so the classifying `cond` can bind the function
  # and test it in one clause, the way it does with a regex's captures.
  defp aggregate_function(body, locale) do
    case Lexicon.aggregate(body, locale) do
      {:ok, function} -> function
      :error -> nil
    end
  end

  defp normalize_name(name) do
    name |> String.split() |> Enum.join(" ")
  end
end
