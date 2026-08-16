defmodule LocalizePad.Line do
  @moduledoc """
  One line of a sheet: its source text, what kind of line it is, and — once
  the sheet has been evaluated — its answer.

  ## Line kinds

  * `:blank` — nothing but whitespace.

  * `:heading` — begins with `#`. Shows no answer, and bounds the range a
    subtotal reaches back over.

  * `:comment` — begins with `//`.

  * `:subtotal` — the word `sum`, alone on a line. Adds up every entry above
    it, back to the previous subtotal or heading.

  * `:declaration` — `name = expression`. Binds a name for the lines below.

  * `:expression` — everything else, including a line carrying a label.

  ## Subtotals are typed, not clicked

  In Soulver a subtotal is made by a keystroke on an empty line, and the sheet
  file records it out of band. A sheet here is plain text first — it has to
  survive being copied into a chat window and pasted back — so the subtotal is
  a word you can type. `sum` on its own line is the marker.

  ## Labels

  `Cost of the iPhone: $999` evaluates to 999; the label is stripped before
  parsing so its digits cannot leak into the arithmetic. A colon must be
  followed by whitespace to count as a label, which is what keeps a clock time
  like `14:45` from being read as a label named "14".

  """

  alias LocalizePad.{Evaluator, Parser, Token, Tokenizer, Value}

  @type kind :: :blank | :heading | :comment | :subtotal | :declaration | :expression

  @type t :: %__MODULE__{
          index: non_neg_integer(),
          source: String.t(),
          kind: kind(),
          label: String.t() | nil,
          name: String.t() | nil,
          expression: String.t() | nil,
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
    :expression,
    :value,
    :formatted,
    :error,
    depends_on: MapSet.new()
  ]

  # A trailing `// ...` comment is stripped from every line before anything
  # else looks at it.
  @trailing_comment ~r{//.*$}u

  @heading ~r/^\s*#/u
  @comment ~r{^\s*//}u

  # A name is a word or phrase: starts with a letter, then letters, digits,
  # spaces and underscores. Requiring a letter first keeps `2 + 2 = 4` from
  # being read as a declaration.
  @declaration ~r/^\s*(\p{L}[\p{L}\p{N}_ ]*?)\s*=\s*(.+)$/u

  # The label runs to the first colon, and the colon must be followed by
  # whitespace. At least one letter is required so that `14:45 ` is a time
  # rather than a label.
  @label ~r/^\s*([^:\n]*\p{L}[^:\n]*):\s+(.*)$/u

  @subtotal_markers ["sum", "subtotal", "total"]

  @doc """
  Classifies a line of source text.

  Classification is purely syntactic — it does not evaluate anything. The
  resulting line has its `:kind`, and where applicable the `:label`, `:name`
  and `:expression` it was split into.

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

  """
  @spec classify(non_neg_integer(), String.t()) :: t()
  def classify(index, source) when is_integer(index) and is_binary(source) do
    line = %__MODULE__{index: index, source: source}
    body = source |> String.replace(@trailing_comment, "") |> String.trim()

    cond do
      Regex.match?(@comment, source) ->
        %{line | kind: :comment}

      Regex.match?(@heading, source) ->
        %{line | kind: :heading}

      body == "" ->
        %{line | kind: :blank}

      String.downcase(body) in @subtotal_markers ->
        %{line | kind: :subtotal}

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

  def evaluate(%__MODULE__{kind: :subtotal} = line, _context) do
    # Subtotals are filled in by the sheet, which is the only thing that knows
    # what range they cover.
    line
  end

  def evaluate(%__MODULE__{expression: expression} = line, context) do
    locale = Map.fetch!(context, :locale)
    variables = Map.fetch!(context, :variables)

    case attempt(expression, context) do
      {:ok, value, ast} ->
        %{line | value: value, formatted: format(value, locale), error: nil}
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
          retry(tokens, context, reason)

        result ->
          result
      end
    end
  end

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

    with {:ok, ast} <- Parser.parse(tokens, variables: Map.keys(variables), locale: locale),
         {:ok, resolved} <- resolve_line_references(ast, answers),
         {:ok, value} <- Evaluator.eval(resolved, variables) do
      {:ok, value, ast}
    end
  end

  defp format(value, locale) do
    case Value.format(value, locale: locale) do
      {:ok, formatted} -> formatted
      {:error, _reason} -> nil
    end
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

  defp normalize_name(name) do
    name |> String.split() |> Enum.join(" ")
  end
end
