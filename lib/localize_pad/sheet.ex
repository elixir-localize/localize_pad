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

  `total/2` adds up the expression lines. Declarations are excluded — a
  declaration names a value for later use, and counting `cost = 550` as an
  entry as well as every line that uses `cost` would double it.

  A line reading `sum`, `average`, `median`, `count`, `min` or `max` does the
  same over the entries above it, back to the previous such line or heading.
  Several of them may sit one under the other, and each reports on the block
  the run as a whole follows rather than on the line above it — `sum` then
  `average` answers for the same entries twice, which is the point of writing
  both.

  Five of the six answer together or not at all. An average is a sum shared
  out, and a median, a minimum and a maximum are orderings, so each needs what
  the sum needs: values of one kind, converted into one unit or one currency.
  What the sum will not add, the others will not average or order either.

  `count` is the exception, because counting asks nothing of the values but
  that they be there. A page of metres and kilograms has no total and no
  middle, and still plainly has two entries on it. It counts what the others
  use, so the sum shared out by the count is always the average.

  Three sheets have a total, and they are the three where one exists to be had:

  * every answer is a number, and they add.

  * every answer is a quantity of one category, so they convert into a common
    unit and add. The result takes the first answer's unit — the sheet's own
    way of writing this measure.

  * every answer is money, and `Money.sum/2` converts them into one currency.
    Where the sheet used several, the total is restated in the reader's own
    currency, since which of the sheet's currencies to report in would
    otherwise be settled by whichever line was typed first.

  Anything else is a page of unlike things, and a page of unlike things has no
  sum. A date or a set of dates is passed over rather than counted against the
  sheet — those were never candidates, so a date beside a shopping list does
  not stop the list having a total.

  Both this and the rule about declarations replaced a tolerant version of
  themselves, and tolerance was the wrong instinct in each. Adding what would
  add and skipping the rest produced a total in whatever unit the topmost line
  happened to use, having silently dropped most of the page — reorder the sheet
  and both the unit and the number changed. Counting a line that reuses another
  line's answer put that answer in twice, and had no repair that was not a
  guess: dropping the referenced line and dropping the line referencing it give
  different totals, both arguable. So the sheet gets neither.

  """

  alias Localize.Unit
  alias LocalizePad.{Evaluator, Line, Locales, Trip, Value}

  @type t :: %__MODULE__{
          locale: Locales.tag(),
          prefer_local: boolean(),
          zone: String.t() | nil,
          lines: [Line.t()]
        }

  defstruct locale: :en, prefer_local: false, zone: nil, lines: []

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

  * `:zone` - the reader's own IANA time zone, which is where `sunrise` is
    asked about when the line names no place. Defaults to `nil`, and a line
    that needs a place then says so rather than being answered for one this
    application picked. See `LocalizePad.Almanac`.

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
    zone = Keyword.get(options, :zone)

    source
    |> String.split("\n")
    |> Enum.with_index()
    |> Enum.map(fn {text, index} -> Line.classify(index, text, locale) end)
    |> then(&%__MODULE__{locale: locale, prefer_local: prefer_local, zone: zone, lines: &1})
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
      zone: sheet.zone,
      # The whole classified document, so the line that opens a trip can read
      # the stops written below it. It reads their *text*, never their answers,
      # which is what keeps the single forward pass honest — see
      # `LocalizePad.Trip`.
      document: sheet.lines,
      trip: %{},
      lines: []
    }

    state = Enum.reduce(sheet.lines, initial, &evaluate_line/2)

    %{sheet | lines: Enum.reverse(state.lines)}
  end

  defp evaluate_line(%Line{kind: :aggregate} = line, state) do
    covered = covered_by(state.lines, line.tags)
    value = aggregate_of(line.aggregate, covered, state.locale, latest_rates())

    # An aggregate depends on every line it reaches back over, so editing any
    # of them marks the aggregate for re-render. Without this the graph would
    # say it depends on nothing, and an editor trusting it would leave a stale
    # answer on screen.
    line = %{
      line
      | value: value,
        formatted: value && format(value, state.locale, state.prefer_local),
        depends_on: MapSet.new(Enum.map(covered, & &1.index))
    }

    %{state | lines: [line | state.lines], answers: put_answer(state.answers, line)}
  end

  # The line that opens a trip plans the whole of it at once, and the stops
  # below simply read the answer that was worked out for them. Planning each
  # stop where it stands would mean re-walking the itinerary once per line.
  defp evaluate_line(%Line{kind: :trip} = line, state) do
    case Trip.plan(state.document, line.index, locale: state.locale) do
      {:ok, summary, answers} ->
        line = %{line | value: summary, formatted: summary, depends_on: covers(answers)}

        %{state | lines: [line | state.lines], trip: Map.merge(state.trip, answers)}

      {:error, reason} ->
        line = %{line | value: nil, formatted: nil, error: reason}

        %{state | lines: [line | state.lines]}
    end
  end

  defp evaluate_line(%Line{kind: kind} = line, state)
       when kind in [:trip_stop, :trip_end] do
    planned(line, state, {:error, :no_trip})
  end

  defp evaluate_line(%Line{} = line, state) do
    # A stop written the label way — `Tokyo: 3 nights` — is an ordinary line
    # everywhere except inside a trip, so it is only claimed when the trip
    # above it planned an answer for this line.
    case Map.fetch(state.trip, line.index) do
      {:ok, _dates} -> planned(line, state, nil)
      :error -> evaluate_expression(line, state)
    end
  end

  defp evaluate_expression(%Line{} = line, state) do
    line = Line.evaluate(line, state)

    state
    |> Map.update!(:lines, &[line | &1])
    |> Map.update!(:answers, &put_answer(&1, line))
    |> bind_variable(line)
  end

  # A stop's answer is the dates it occupies, worked out when the trip was
  # planned. Outside a trip there is nothing to work them out from, and the
  # line says so rather than going quietly blank.
  defp planned(line, state, fallback) do
    line =
      case Map.fetch(state.trip, line.index) do
        {:ok, dates} -> %{line | value: dates, formatted: dates}
        :error -> %{line | value: nil, formatted: nil, error: error_of(fallback)}
      end

    %{state | lines: [line | state.lines], answers: put_answer(state.answers, line)}
  end

  defp error_of({:error, reason}), do: reason
  defp error_of(nil), do: nil

  defp covers(answers), do: answers |> Map.keys() |> MapSet.new()

  # The block an aggregate reports on, given the lines above it in the order
  # they were accumulated — most recent first.
  #
  # The leading run of aggregates is skipped rather than treated as a boundary,
  # which is what lets `sum` / `average` / `median` stand one under the other
  # and all three answer for the same entries. Reading `average` as a block
  # bounded by the `sum` above it would give it nothing to average, and the
  # obvious way to write two functions would produce one answer and one blank.
  #
  # Blanks and comments go with them, so a run may be spaced out and explained.
  # Neither separates anything anywhere else in a sheet — only a heading or an
  # aggregate bounds a block — and making them boundaries here alone would be a
  # rule with one instance. A sheet that wrote a line of prose between its
  # subtotal and its average had the average report on nothing at all.
  defp covered_by(lines, []) do
    lines
    |> Enum.drop_while(&(&1.kind in [:aggregate, :blank, :comment]))
    |> Enum.take_while(&(&1.kind not in [:aggregate, :heading]))
    |> Enum.reverse()
  end

  # A tagged aggregate reports on its tag rather than on its neighbours, so it
  # reaches back over the whole section — past blanks, past plain lines, and
  # past other aggregates. `sum #ann` and `sum #bob` under one another must
  # each see every tagged line above them, and a block boundary between them
  # would leave the second reporting on what the first had already passed.
  #
  # A heading still stops it. A tag means one thing per section of a sheet:
  # `#food` under `# Rome` and `#food` under `# Paris` are two answers, which
  # is what makes a heading worth typing.
  #
  # Naming several tags narrows rather than widens — `sum #ann #food` is what
  # Ann spent on food, not everything either word touches. Widening has a
  # spelling already, which is to tag the lines with one word.
  defp covered_by(lines, tags) do
    lines
    |> Enum.take_while(&(&1.kind != :heading))
    |> Enum.filter(&tagged?(&1, tags))
    |> Enum.reverse()
  end

  defp tagged?(%Line{tags: carried}, tags), do: Enum.all?(tags, &(&1 in carried))

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

  * `rates` - the exchange rates used to total a sheet written in more than one
    currency, in the form `Money.sum/2` takes. Defaults to the latest retrieved
    rates.

  ### Returns

  * The total as a value.

  * `nil` when the sheet has no total: nothing in it can be added up, its
    answers are of kinds that will not combine, or one line's answer is already
    inside another's and counting both would double it.

  ### Examples

      iex> sheet = LocalizePad.Sheet.new("19\\n22\\n# a heading\\n1")
      iex> LocalizePad.Sheet.total(sheet)
      42

      iex> sheet = LocalizePad.Sheet.new("100 EUR\\n11 USD", locale: "en-AU")
      iex> rates = %{EUR: Decimal.new(1), USD: Decimal.new("1.1"), AUD: Decimal.new("1.7")}
      iex> Money.equal?(LocalizePad.Sheet.total(sheet, rates), Money.new(:AUD, 187))
      true

  """
  @spec total(t(), Money.ExchangeRates.t() | {:ok, Money.ExchangeRates.t()} | {:error, term()}) ::
          Evaluator.value() | nil
  def total(sheet, rates \\ latest_rates())

  def total(%__MODULE__{lines: lines, locale: locale}, rates) do
    aggregate_of(:sum, lines, locale, rates)
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

  # ── Aggregating ─────────────────────────────────────────────────────────

  # A sheet has an answer when its own answers are one kind of thing, each
  # standing on its own. `independent?/2` decides the second; `combine/4` the
  # first.
  #
  # Values that were never candidates are passed over rather than counted
  # against the sheet. A date beside a shopping list does not stop the list
  # having a total; it simply is not part of one. It is not part of the count
  # either, which is what keeps an average from being divided by the dates.
  defp aggregate_of(function, lines, locale, rates) do
    counted = Enum.filter(lines, &(&1.kind == :expression and not is_nil(&1.value)))

    if independent?(counted, transitive_dependencies(lines)) do
      counted
      |> Enum.map(& &1.value)
      |> Enum.filter(&summable?/1)
      |> combine(function, locale, rates)
    end
  end

  # Three shapes combine: numbers, quantities of one kind, and money. Anything
  # else is a page of unlike things, and a page of unlike things has no answer
  # — not a partial one taken over whichever values happened to agree with the
  # topmost line.
  defp combine([], _function, _locale, _rates), do: nil

  defp combine(values, :sum, locale, rates), do: add_together(values, locale, rates)

  # The average is the sum shared out, so it is exactly as answerable as the
  # sum: a page that will not add will not average either, and one that adds
  # in the reader's currency averages in it too.
  defp combine(values, :average, locale, rates) do
    case add_together(values, locale, rates) do
      nil -> nil
      total -> divide(total, length(values))
    end
  end

  # The median needs an order rather than a sum, and an order over money or
  # quantities means putting them in one currency or one unit first. An even
  # count has no middle value, so it takes the mean of the two either side —
  # which is the usual convention and the only one that does not silently
  # prefer the lower half.
  defp combine(values, :median, locale, rates) do
    case ordered(values, locale, rates) do
      {:ok, sorted} -> middle(sorted, locale, rates)
      :error -> nil
    end
  end

  # The smallest and largest come out of the same ordering, and out of it
  # already converted — the smallest of a metre and 50 cm is half a metre,
  # written in the unit the sheet chose, exactly as the sum and the median
  # are.
  defp combine(values, :minimum, locale, rates), do: end_of(values, locale, rates, &List.first/1)
  defp combine(values, :maximum, locale, rates), do: end_of(values, locale, rates, &List.last/1)

  # Counting asks nothing of the values but that they be entries, so it
  # answers where the others refuse: a page of metres and kilograms has no
  # total and no middle, and still plainly has two things on it.
  #
  # What it counts is what the others use, which is what keeps the sum shared
  # out by the count equal to the average. A date is not an entry here for the
  # same reason it is not part of the total.
  defp combine(values, :count, _locale, _rates), do: length(values)

  defp end_of(values, locale, rates, pick) do
    case ordered(values, locale, rates) do
      {:ok, sorted} -> pick.(sorted)
      :error -> nil
    end
  end

  defp middle(values, locale, rates) do
    count = length(values)
    above = div(count, 2)

    if rem(count, 2) == 1 do
      Enum.at(values, above)
    else
      case values |> Enum.slice(above - 1, 2) |> add_together(locale, rates) do
        nil -> nil
        total -> divide(total, 2)
      end
    end
  end

  # Dividing is how both an average and an even median are finished, and each
  # shape has its own arithmetic for it. Money keeps more decimal places than
  # its currency shows; the formatter rounds, so the sheet reports a currency
  # amount rather than a repeating fraction.
  defp divide(value, count) when is_number(value), do: value / count
  defp divide(%Unit{} = unit, count), do: unwrap(Unit.Math.div(unit, count))
  defp divide(%Money{} = money, count), do: unwrap(Money.div(money, count))

  defp unwrap({:ok, value}), do: value
  defp unwrap({:error, _reason}), do: nil

  # Sorting is only defined within a shape, and only once the values are
  # commensurable: euros and dollars compare after conversion, metres and
  # centimetres after conversion, and metres and kilograms not at all.
  defp ordered(values, locale, rates) do
    cond do
      Enum.all?(values, &is_number/1) -> {:ok, Enum.sort(values)}
      Enum.all?(values, &match?(%Unit{}, &1)) -> order_units(values)
      Enum.all?(values, &match?(%Money{}, &1)) -> order_money(values, locale, rates)
      true -> :error
    end
  end

  # Converted into the first answer's unit, for the same reason the sum is: it
  # is the sheet's own way of writing this measure. A unit whose value is a
  # list — `5 foot 10 inch` — has no single number to order by and refuses.
  defp order_units([first | _rest] = values) do
    with {:ok, converted} <- convert_each(values, &Unit.convert(&1, first.name)),
         true <- Enum.all?(converted, &comparable_amount?/1) do
      {:ok, Enum.sort_by(converted, &decimal(&1.value), {:asc, Decimal})}
    else
      _incomparable -> :error
    end
  end

  # A page in one currency is ordered in it. A page in several is ordered in
  # the reader's own, which is the currency its median will be reported in —
  # ordering in one and answering in another could put the answer out of step
  # with the values it came from.
  defp order_money(values, locale, rates) do
    if one_currency?(values) do
      {:ok, sort_money(values)}
    else
      currency = reporting_currency(values, locale)

      case convert_each(values, &Money.to_currency(&1, currency, rates)) do
        {:ok, converted} -> {:ok, sort_money(converted)}
        :error -> :error
      end
    end
  end

  # The reader's own currency, or the topmost value's where the locale names
  # none — a page still has to be put in some one currency to be ordered.
  defp reporting_currency([first | _rest], locale) do
    case Localize.Currency.currency_from_locale(locale) do
      {:ok, currency} -> currency
      {:error, _reason} -> first.currency
    end
  end

  defp sort_money(values), do: Enum.sort_by(values, & &1.amount, {:asc, Decimal})

  # All or nothing. A median taken over the subset that happened to convert is
  # the median of a different page.
  defp convert_each(values, conversion) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, converted} ->
      case conversion.(value) do
        {:ok, value} -> {:cont, {:ok, converted ++ [value]}}
        {:error, _reason} -> {:halt, :error}
      end
    end)
  end

  defp comparable_amount?(%Unit{value: value}), do: is_number(value) or match?(%Decimal{}, value)

  defp decimal(%Decimal{} = value), do: value
  defp decimal(value) when is_integer(value), do: Decimal.new(value)
  defp decimal(value) when is_float(value), do: Decimal.from_float(value)

  defp add_together(values, locale, rates) do
    cond do
      Enum.all?(values, &is_number/1) -> Enum.sum(values)
      Enum.all?(values, &match?(%Unit{}, &1)) -> add_units(values)
      Enum.all?(values, &match?(%Money{}, &1)) -> add_money(values, locale, rates)
      true -> nil
    end
  end

  # Same category or no total. `Unit.Math.add/2` is the authority on that, and
  # it converts as it goes, so metres and centimetres come out as one length
  # and metres and kilograms come out as nothing.
  #
  # The result takes the first answer's unit, which is the sheet's own choice
  # of how to write this measure rather than one made for it.
  defp add_units([first | rest]) do
    Enum.reduce_while(rest, first, fn unit, total ->
      case Unit.Math.add(total, unit) do
        {:ok, sum} -> {:cont, sum}
        {:error, _reason} -> {:halt, nil}
      end
    end)
  end

  # No rates is an empty map rather than an error, because `Money.sum/2` refuses
  # outright when handed `{:error, _}` — including for a list in one currency,
  # which needs no rate at all. A sheet of dollars still totals on a machine
  # that has never fetched a rate; only a sheet of dollars *and* euros cannot.
  defp latest_rates do
    case Money.ExchangeRates.latest_rates() do
      {:ok, rates} -> rates
      {:error, _reason} -> %{}
    end
  end

  # `Money.sum/2` converts each amount into the first one's currency, using the
  # rates already cached for `EUR 200 in AUD`. With no rate for a currency on
  # the page it returns an error, and an error is the honest total.
  defp add_money(values, locale, rates) do
    case Money.sum(values, rates) do
      {:ok, sum} -> in_readers_currency(sum, values, locale, rates)
      {:error, _reason} -> nil
    end
  end

  # Where a sheet used one currency throughout, that is what it is about and
  # the sum is already in it — converting a page of euros into pounds would be
  # answering a question nobody asked, and would need a rate to do it.
  #
  # Where a sheet mixed them, `Money.sum/2` reports in whichever currency the
  # topmost line happened to use, and that is an accident of line order. The
  # reader's own currency is the one non-arbitrary answer.
  defp in_readers_currency(sum, values, locale, rates) do
    if one_currency?(values) do
      sum
    else
      convert(sum, Localize.Currency.currency_from_locale(locale), rates)
    end
  end

  defp one_currency?(values), do: values |> Enum.uniq_by(& &1.currency) |> length() == 1

  # A total that cannot be restated in the reader's currency is still a correct
  # total, so it is reported as it stands rather than withheld.
  defp convert(sum, {:ok, currency}, rates) do
    case Money.to_currency(sum, currency, rates) do
      {:ok, converted} -> converted
      {:error, _reason} -> sum
    end
  end

  defp convert(sum, _no_currency, _rates), do: sum

  # A total adds up answers that stand on their own, and `@3 + 100` does not:
  # line 3's answer is already inside it, so adding both puts that answer into
  # the total twice. The sample sheet read `542` where its independent answers
  # come to `401`, and nothing on screen said which lines had been counted.
  #
  # There is no repair for it that is not a guess. Dropping the referenced line
  # and dropping the line that references it give different totals, both
  # defensible, so the sheet gets neither.
  #
  # Variables count as references. `hotel * 3` reuses line 4's answer exactly
  # as `@4 * 3` does; the graph records both as edges and the double count is
  # identical either way.
  defp independent?(counted, reaches) do
    indexes = MapSet.new(counted, & &1.index)

    Enum.all?(counted, fn line ->
      reaches
      |> Map.get(line.index, MapSet.new())
      |> MapSet.disjoint?(indexes)
    end)
  end

  # Every line each line reaches back to, following the chain rather than the
  # single step. A declaration in the middle would otherwise hide the edge:
  # `total = @1` then `total + 5` depends directly on a line that is not itself
  # counted, and only the closure shows that line 1's answer is in there.
  #
  # One pass suffices because a line can only reference lines above it, so by
  # the time it is reached its dependencies are already resolved.
  defp transitive_dependencies(lines) do
    Enum.reduce(lines, %{}, fn line, reaches ->
      inherited =
        Enum.reduce(line.depends_on, line.depends_on, fn index, accumulated ->
          MapSet.union(accumulated, Map.get(reaches, index, MapSet.new()))
        end)

      Map.put(reaches, line.index, inherited)
    end)
  end

  defp summable?(value), do: Value.kind(value) in [:number, :quantity, :money]

  defp format(value, locale, prefer_local) do
    case Value.format(value, locale: locale, prefer_local: prefer_local) do
      {:ok, formatted} -> formatted
      {:error, _reason} -> nil
    end
  end
end
