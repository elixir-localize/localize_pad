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
  alias LocalizePad.{Evaluator, Line, Locales, Value}

  @type t :: %__MODULE__{
          locale: Locales.tag(),
          prefer_local: boolean(),
          lines: [Line.t()]
        }

  defstruct locale: :en, prefer_local: false, lines: []

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
    locale = options |> Keyword.get_lazy(:locale, &Localize.get_locale/0) |> resolve_locale()

    prefer_local = Keyword.get(options, :prefer_local, false)

    source
    |> String.split("\n")
    |> Enum.with_index()
    |> Enum.map(fn {text, index} -> Line.classify(index, text, locale) end)
    |> then(&%__MODULE__{locale: locale, prefer_local: prefer_local, lines: &1})
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
      prefer_local: sheet.prefer_local,
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
        formatted: value && format(value, state.locale, state.prefer_local),
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
      updated = List.replace_at(lines, index, Line.classify(index, source, sheet.locale))
      evaluate(%{sheet | lines: updated})
    else
      sheet
    end
  end

  @doc """
  Renders the sheet as Markdown, with its answers.

  ## Round-tripping, for free

  The answers are written as `//` comments, which is the sheet's *own* syntax
  for text the engine ignores. So the exported block can be pasted straight
  back into a sheet and evaluates to exactly what it says — the answers are
  both readable and inert.

  That is worth more than a prettier table. A download is a save, and a save
  that cannot be reopened is a screenshot.

  ## The locale is part of the document

  `1.234,5` is a different number in `de` than in `en`, so a sheet without its
  locale is ambiguous rather than portable. It is recorded in the header.

  ### Arguments

  * `sheet` - an evaluated sheet.

  * `options` - a keyword list of options.

  ### Options

  * `:title` - the heading to put at the top. Defaults to `"LocalizePad sheet"`.

  ### Returns

  * A Markdown string.

  ### Examples

      iex> markdown =
      ...>   "19 + 22" |> LocalizePad.Sheet.new(locale: :en) |> LocalizePad.Sheet.to_markdown()
      iex> markdown =~ "19 + 22   // 41"
      true

      iex> markdown =
      ...>   "19 + 22" |> LocalizePad.Sheet.new(locale: :de) |> LocalizePad.Sheet.to_markdown()
      iex> markdown =~ "Locale: `de`"
      true

  """
  @spec to_markdown(t(), keyword()) :: String.t()
  def to_markdown(%__MODULE__{} = sheet, options \\ []) do
    title = Keyword.get(options, :title, "LocalizePad sheet")
    width = column_width(sheet)

    body = Enum.map_join(sheet.lines, "\n", &markdown_line(&1, width))

    [
      "# #{title}",
      "",
      "Locale: `#{sheet.locale}`",
      "",
      "```",
      String.trim_trailing(body),
      "```",
      total_line(sheet)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  # Answers line up in a column, as they do on screen. The width is the longest
  # source line, so nothing is truncated and the block stays scannable.
  @doc """
  Reads a sheet back out of the Markdown `to_markdown/2` writes.

  ## What has to be undone

  The export writes each answer as a `//` comment aligned into a column, which
  is what makes it paste back in as a working sheet. It also makes it grow: a
  file imported and exported again would carry `// 41   // 41`, and once more
  after that. So the answer column is stripped on the way in.

  It is stripped by matching the separator the exporter writes — three spaces
  before the slashes. That is a convention, not a proof: a comment somebody
  typed by hand with exactly three spaces in front of it is indistinguishable
  from a generated one and will be absorbed. Comments written with one or two
  spaces survive, as does a whole line that is a comment. The alternative was
  keeping the answers, which compounds, or re-evaluating every line to see
  whether the comment matches its own answer, which is slower and still wrong
  for a line whose comment happens to be its answer.

  ## Anything else is a sheet already

  A file with no fenced block is taken whole. Someone pasting a plain list of
  sums into a `.txt` has made a sheet, and refusing it because it lacks a
  header this program wrote would be pedantry.

  ### Arguments

  * `markdown` - the file's contents.

  ### Returns

  * `{:ok, source, locale}`, where `locale` is `nil` when the file does not
    name one — the caller keeps whatever locale it is already using rather
    than having one guessed for it.

  * `{:error, :empty}` when there is nothing to read. Upload is untrusted
    input; this never raises.

  ### Examples

      iex> markdown = LocalizePad.Sheet.new("19 + 22", locale: :en) |> LocalizePad.Sheet.to_markdown()
      iex> {:ok, source, locale} = LocalizePad.Sheet.from_markdown(markdown)
      iex> {source, to_string(locale)}
      {"19 + 22", "en"}

      iex> LocalizePad.Sheet.from_markdown("2 + 2\\n3 * 3")
      {:ok, "2 + 2\\n3 * 3", nil}

      iex> LocalizePad.Sheet.from_markdown("   ")
      {:error, :empty}

  """
  @spec from_markdown(String.t()) :: {:ok, String.t(), Locales.tag() | nil} | {:error, :empty}
  def from_markdown(markdown) when is_binary(markdown) do
    source =
      markdown
      |> fenced_block()
      |> String.split("\n")
      |> Enum.map_join("\n", &strip_answer/1)
      |> String.trim_trailing()

    if String.trim(source) == "" do
      {:error, :empty}
    else
      {:ok, source, stated_locale(markdown)}
    end
  end

  def from_markdown(_markdown), do: {:error, :empty}

  # The first fenced block, or the whole document when there is none.
  defp fenced_block(markdown) do
    case String.split(markdown, ~r/^```.*$/m, parts: 3) do
      [_before, block, _after] -> String.trim(block, "\n")
      _no_fence -> markdown
    end
  end

  @exported_answer ~r/[ ]{3}\/\/ .*$/

  # The padding that aligned the answer column goes with the answer. Trailing
  # whitespace means nothing to a sheet — `Line.classify/2` trims it anyway —
  # so removing it is what makes an import and re-export stable rather than
  # slowly accumulating spaces.
  defp strip_answer(line) do
    line
    |> String.replace(@exported_answer, "")
    |> String.trim_trailing()
  end

  # A sheet holds a language tag, not a name for one. Callers pass `:en` or
  # `"en-AU"` and that is fine at the door; past it, every line is evaluated
  # against a resolved tag so nothing downstream has to guess which English.
  #
  # A locale that cannot be resolved falls back to the current one rather than
  # raising. `new/2` is on the render path, and a bad `:locale` option must not
  # be able to take a page down.
  defp resolve_locale(locale) do
    case Locales.resolve(locale) do
      {:ok, language_tag} -> language_tag
      {:error, _reason} -> Localize.get_locale()
    end
  end

  # The whole tag, so an exported `en-AU` sheet reopens as `en-AU` rather than
  # as some other English. A tag this cannot honour is treated as unstated —
  # the sheet then opens in the reader's own locale, which is visible in the
  # header, rather than in a language it silently substituted.
  defp stated_locale(markdown) do
    with [_whole, name] <- Regex.run(~r/^Locale:\s*`([^`]+)`/m, markdown),
         {:ok, tag} <- Locales.resolve(name) do
      tag
    else
      _unstated -> nil
    end
  end

  defp column_width(%__MODULE__{lines: lines}) do
    lines
    |> Enum.filter(& &1.formatted)
    |> Enum.map(&String.length(String.trim_trailing(&1.source)))
    |> Enum.max(fn -> 0 end)
  end

  defp markdown_line(%Line{formatted: nil} = line, _width), do: String.trim_trailing(line.source)

  defp markdown_line(%Line{} = line, width) do
    source = String.trim_trailing(line.source)

    String.pad_trailing(source, width) <> "   // " <> exported_answer(line)
  end

  # The margin truncates a set of dates because it has one line; a file does
  # not, and an export that drops half its answer is not a save.
  defp exported_answer(%Line{value: value, formatted: formatted}) do
    case Value.detail(value, locale: Localize.get_locale()) do
      {:ok, parts} -> Enum.join(parts, ", ")
      {:error, _reason} -> formatted
    end
  end

  defp total_line(%__MODULE__{} = sheet) do
    case total(sheet) do
      nil ->
        nil

      total ->
        case Value.format(total, locale: sheet.locale) do
          {:ok, formatted} -> "\n**Total:** #{formatted}"
          {:error, _reason} -> nil
        end
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

  defp format(value, locale, prefer_local) do
    case Value.format(value, locale: locale, prefer_local: prefer_local) do
      {:ok, formatted} -> formatted
      {:error, _reason} -> nil
    end
  end
end
