defmodule LocalizePad.Sheet do
  @moduledoc """
  A sheet: an ordered list of lines, evaluated top to bottom, with a running
  total and a dependency graph.

  ## Why top to bottom is enough

  A name must be declared before it is used, and a line reference may only
  point upward. Together those two rules make a single forward pass correct —
  there is no fixed point to iterate to and no cycle to detect, which is a
  large simplification over a spreadsheet.

  ## The dependency graph

  Every line records the lines it depends on, whether the dependency was
  written as `@3` or as a variable that line 3 declared. Recalculation still
  re-runs the whole sheet, because at notepad scale that costs microseconds and
  correctness beats cleverness. The graph exists for the things a full pass
  cannot give: knowing which answers actually changed so the editor can
  re-render only those, finding what a rename must rewrite, and telling the
  user what a line would break if they deleted it.

  ## Totals

  `total/1` adds up the expression lines. Declarations are excluded — a
  declaration names a value for later use, and counting `cost = 550` as an
  entry as well as every line that uses `cost` would double it.

  Values that cannot be added to the running total are skipped rather than
  poisoning it. A sheet mixing dollars and kilometres still totals its dollars.

  """

  alias Localize.Unit
  alias LocalizePad.{Evaluator, Line, Value}

  @type t :: %__MODULE__{
          locale: atom(),
          lines: [Line.t()]
        }

  defstruct locale: :en, lines: []

  @doc """
  Builds and evaluates a sheet from its source text.

  ### Arguments

  * `source` - the whole sheet as text, one line per line.

  * `options` - a keyword list of options.

  ### Options

  * `:locale` - the locale that governs how numbers and units are read and
    written. Defaults to `Localize.get_locale/0`. Changing it and rebuilding
    re-reads the sheet, which is the point: `1.234,5` is a different number in
    `:de` than in `:en`.

  ### Returns

  * A `t:LocalizePad.Sheet.t/0` with every line evaluated.

  ### Examples

      iex> sheet = LocalizePad.Sheet.new("2 + 2\\n3 meters to feet", locale: :en)
      iex> Enum.map(sheet.lines, & &1.formatted)
      ["4", "9.84252 feet"]

  """
  @spec new(String.t(), keyword()) :: t()
  def new(source, options \\ []) when is_binary(source) do
    locale = Keyword.get_lazy(options, :locale, &Localize.get_locale/0)

    source
    |> String.split("\n")
    |> Enum.with_index()
    |> Enum.map(fn {text, index} -> Line.classify(index, text) end)
    |> then(&%__MODULE__{locale: locale, lines: &1})
    |> evaluate()
  end

  @doc """
  Re-evaluates a sheet.

  ### Arguments

  * `sheet` - the sheet to evaluate.

  ### Returns

  * The sheet with every line's value, formatted answer, error and
    dependencies brought up to date.

  """
  @spec evaluate(t()) :: t()
  def evaluate(%__MODULE__{} = sheet) do
    initial = %{
      variables: %{},
      answers: %{},
      declared_at: %{},
      locale: sheet.locale,
      lines: []
    }

    state = Enum.reduce(sheet.lines, initial, &evaluate_line/2)

    %{sheet | lines: Enum.reverse(state.lines)}
  end

  defp evaluate_line(%Line{kind: :subtotal} = line, state) do
    covered =
      state.lines
      |> Enum.take_while(&(&1.kind not in [:subtotal, :heading]))
      |> Enum.reverse()

    value = sum_of(covered)

    # A subtotal depends on every line it reaches back over, so editing any of
    # them marks the subtotal for re-render. Without this the graph would say a
    # subtotal depends on nothing, and an editor trusting it would leave a
    # stale answer on screen.
    line = %{
      line
      | value: value,
        formatted: value && format(value, state.locale),
        depends_on: MapSet.new(Enum.map(covered, & &1.index))
    }

    %{state | lines: [line | state.lines], answers: put_answer(state.answers, line)}
  end

  defp evaluate_line(%Line{} = line, state) do
    line = Line.evaluate(line, state)

    state
    |> Map.update!(:lines, &[line | &1])
    |> Map.update!(:answers, &put_answer(&1, line))
    |> bind_variable(line)
  end

  defp put_answer(answers, %Line{value: nil}), do: answers
  defp put_answer(answers, %Line{index: index, value: value}), do: Map.put(answers, index, value)

  # A declaration binds its name for the lines below, and re-declaring shadows
  # the earlier value from that point on.
  defp bind_variable(state, %Line{kind: :declaration, name: name, value: value})
       when not is_nil(name) and not is_nil(value) do
    state
    |> Map.update!(:variables, &Map.put(&1, name, value))
    |> Map.update!(
      :declared_at,
      &Map.put(&1, name, state |> Map.fetch!(:lines) |> hd() |> Map.fetch!(:index))
    )
  end

  defp bind_variable(state, _line), do: state

  @doc """
  Returns the total of the sheet's expression lines.

  ### Arguments

  * `sheet` - an evaluated sheet.

  ### Returns

  * The total as a value, or `nil` when nothing in the sheet can be added up.

  ### Examples

      iex> sheet = LocalizePad.Sheet.new("19\\n22\\n# a heading\\n1")
      iex> LocalizePad.Sheet.total(sheet)
      42

  """
  @spec total(t()) :: Evaluator.value() | nil
  def total(%__MODULE__{lines: lines}) do
    sum_of(lines)
  end

  @doc """
  Returns the lines that depend on the given line, directly or transitively.

  ### Arguments

  * `sheet` - an evaluated sheet.

  * `index` - the zero-based index of the line to trace from.

  ### Returns

  * A sorted list of line indexes. The line itself is not included.

  ### Examples

      iex> sheet = LocalizePad.Sheet.new("cost = 10\\ncost * 2\\n@2 + 1")
      iex> LocalizePad.Sheet.dependents(sheet, 0)
      [1, 2]

  """
  @spec dependents(t(), non_neg_integer()) :: [non_neg_integer()]
  def dependents(%__MODULE__{lines: lines}, index) do
    lines
    |> Enum.reduce(MapSet.new([index]), fn line, reached ->
      if line.depends_on |> MapSet.intersection(reached) |> Enum.any?() do
        MapSet.put(reached, line.index)
      else
        reached
      end
    end)
    |> MapSet.delete(index)
    |> Enum.sort()
  end

  @doc """
  Replaces one line's source and re-evaluates the sheet.

  ### Arguments

  * `sheet` - the sheet to update.

  * `index` - the zero-based index of the line to replace.

  * `source` - the line's new text.

  ### Returns

  * The re-evaluated sheet. An index outside the sheet returns it unchanged.

  ### Examples

      iex> sheet = LocalizePad.Sheet.new("2 + 2")
      iex> sheet = LocalizePad.Sheet.put_line(sheet, 0, "3 + 3")
      iex> LocalizePad.Sheet.total(sheet)
      6

  """
  @spec put_line(t(), non_neg_integer(), String.t()) :: t()
  def put_line(%__MODULE__{lines: lines} = sheet, index, source)
      when is_integer(index) and is_binary(source) do
    if index in 0..(length(lines) - 1)//1 do
      updated = List.replace_at(lines, index, Line.classify(index, source))
      evaluate(%{sheet | lines: updated})
    else
      sheet
    end
  end

  @doc """
  Renders the sheet as source text.

  ### Arguments

  * `sheet` - the sheet to render.

  ### Returns

  * The sheet's lines joined with newlines — the same text `new/2` was given.

  ### Examples

      iex> "2 + 2\\n3 + 3" |> LocalizePad.Sheet.new() |> LocalizePad.Sheet.to_source()
      "2 + 2\\n3 + 3"

  """
  @spec to_source(t()) :: String.t()
  def to_source(%__MODULE__{lines: lines}) do
    Enum.map_join(lines, "\n", & &1.source)
  end

  # ── Summing ─────────────────────────────────────────────────────────────

  # Only expression lines count. Values that will not add to the running total
  # are skipped, so a sheet mixing currencies and distances still totals what
  # it can.
  defp sum_of(lines) do
    lines
    |> Enum.filter(&(&1.kind == :expression and not is_nil(&1.value)))
    |> Enum.reduce(nil, fn line, total -> accumulate(total, line.value) end)
  end

  # Only a value that could sensibly be added to others may seed the total. A
  # date cannot: adding up the dates in a sheet is meaningless, and letting one
  # seed the accumulator made the total read as whatever date appeared first
  # while every real number below it was silently skipped.
  defp accumulate(nil, value) do
    if summable?(value), do: value
  end

  defp accumulate(total, value) when is_number(total) and is_number(value) do
    total + value
  end

  defp accumulate(%Unit{} = total, %Unit{} = value) do
    case Unit.Math.add(total, value) do
      {:ok, sum} -> sum
      {:error, _reason} -> total
    end
  end

  defp accumulate(%Money{} = total, %Money{} = value) do
    case Money.add(total, value) do
      {:ok, sum} -> sum
      # Two different currencies cannot be added without a rate, so the second
      # is skipped rather than the total being abandoned.
      {:error, _reason} -> total
    end
  end

  defp accumulate(total, _value), do: total

  defp summable?(value), do: Value.kind(value) in [:number, :quantity, :money]

  defp format(value, locale) do
    case Value.format(value, locale: locale) do
      {:ok, formatted} -> formatted
      {:error, _reason} -> nil
    end
  end
end
