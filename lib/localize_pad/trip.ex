defmodule LocalizePad.Trip do
  @moduledoc """
  Planning an itinerary: a start date, a run of stops, and whether the whole
  thing fits in the time you have.

      trip from March 3, 2026 to March 22, 2026
      3 nights in Tokyo
      5 nights in Kyoto
      4 nights in Osaka
      trip ends March 22, 2026

  Each stop answers with the dates you are there, the opening line answers with
  the length of the trip and how it compares with the time budgeted, and
  changing any one stop moves every stop below it.

  ## Two spellings, because people write both

  A stop is `3 nights in Tokyo` or `Tokyo: 3 nights`. The first reads as prose
  and is unambiguous on its own. The second is the label syntax the sheet
  already has, so the place is the label and the nights are its value — and it
  is only a stop *inside a trip*, since `Tokyo: 3 nights` on an ordinary sheet
  is an ordinary line and must stay one.

  `days` is accepted wherever `nights` is, and means the same span. A traveller
  who writes `3 days in Osaka` has the same three days on the calendar as one
  who writes `3 nights`; which of the two words is the more accurate name for
  that span is an argument about hotels rather than about dates.

  ## Why the trip is read as a block

  A sheet is evaluated top to bottom in one pass, and every answer depends only
  on lines above it. A trip breaks that shape: the opening line reports on
  stops written below it.

  It is not a real exception, because what the opening line reads is the
  *text* below it rather than the *answers* below it. Classification is purely
  syntactic and has already run for the whole sheet, so the stops can be
  counted without evaluating anything. No answer waits on an answer beneath it,
  and the single forward pass survives intact.

  ## English only, for now

  The vocabulary here — `trip`, `nights`, `in` — is this application's own,
  like `LocalizePad.Finance` and `LocalizePad.Almanac`. The *answers* are not:
  the dates of each stop come back as a CLDR date interval, so a German sheet
  reads `03.03.2026 – 06.03.2026` where an English one reads `Mar 3 – 6, 2026`,
  and neither spelling is written down here.

  """

  use Localize.Message.Sigils,
    backend: LocalizePad.Gettext,
    sigils: [domain: "answers"]

  alias LocalizePad.{Line, Temporal, Tokenizer}

  # `trip`, then anything: `trip from March 3`, `trip: March 3 to March 22`,
  # `trip starting March 3`. What follows is handed to the tokenizer rather
  # than matched here, so every date form the sheet reads is a date form a trip
  # can start on.
  @opening ~r/^trip\b[\s:]*(.*)$/iu

  # Checked before the opening, which it would otherwise match.
  @ending ~r/^trip\s+(?:ends?|ending|finishes|finishing)\b[\s:]*(.*)$/iu

  @stop ~r/^(\d+)\s+(nights?|days?)\s+in\s+(.+)$/iu

  # The label form's value, once the label has been taken off: `Tokyo: 3 nights`
  # arrives here as `3 nights`.
  @counted ~r/^(\d+)\s+(nights?|days?)$/iu

  @doc """
  Classifies a line as part of a trip, by shape alone.

  ### Arguments

  * `body` - the line's text, with any comment and tags already taken off.

  ### Returns

  * `{:ok, :trip}` for the line that opens one, `{:ok, :trip_end}` for the line
    that closes one, and `{:ok, :trip_stop}` for a stop written the long way.

  * `:error` for everything else, which is nearly every line.

  ### Examples

      iex> LocalizePad.Trip.classify("trip from March 3, 2026")
      {:ok, :trip}

      iex> LocalizePad.Trip.classify("trip ends March 22, 2026")
      {:ok, :trip_end}

      iex> LocalizePad.Trip.classify("3 nights in Tokyo")
      {:ok, :trip_stop}

      iex> LocalizePad.Trip.classify("Tokyo: 3 nights")
      :error

  """
  @spec classify(String.t()) :: {:ok, :trip | :trip_end | :trip_stop} | :error
  def classify(body) when is_binary(body) do
    cond do
      Regex.match?(@ending, body) -> {:ok, :trip_end}
      Regex.match?(@opening, body) -> {:ok, :trip}
      Regex.match?(@stop, body) -> {:ok, :trip_stop}
      true -> :error
    end
  end

  @doc """
  Reads a line as a stop, in either spelling.

  ### Arguments

  * `line` - a classified line.

  ### Returns

  * `{:ok, nights, place}` where nights is the number of days the stop
    occupies.

  * `:error` when the line is not a stop.

  ### Examples

      iex> LocalizePad.Trip.stop(LocalizePad.Line.classify(0, "3 nights in Tokyo"))
      {:ok, 3, "Tokyo"}

      iex> LocalizePad.Trip.stop(LocalizePad.Line.classify(0, "Kyoto: 5 nights"))
      {:ok, 5, "Kyoto"}

      iex> LocalizePad.Trip.stop(LocalizePad.Line.classify(0, "19 + 22"))
      :error

  """
  @spec stop(Line.t()) :: {:ok, pos_integer(), String.t()} | :error
  def stop(%Line{kind: :trip_stop, expression: body}) do
    case Regex.run(@stop, body) do
      [_whole, count, _unit, place] -> {:ok, String.to_integer(count), String.trim(place)}
      nil -> :error
    end
  end

  # The label spelling. Only ever a stop inside a trip block, which is the
  # caller's business rather than this function's — `Tokyo: 3 nights` on a
  # sheet with no trip on it is an ordinary labelled line and stays one.
  def stop(%Line{kind: :expression, label: place, expression: body})
      when is_binary(place) and is_binary(body) do
    case Regex.run(@counted, String.trim(body)) do
      [_whole, count, _unit] -> {:ok, String.to_integer(count), place}
      nil -> :error
    end
  end

  def stop(%Line{}), do: :error

  @doc """
  Plans the trip a line opens.

  ### Arguments

  * `document` - every classified line of the sheet.

  * `index` - the index of the opening line.

  * `options` - a keyword list of options.

  ### Options

  * `:locale` - the locale the dates are read and written in.

  ### Returns

  * `{:ok, summary, answers}` where summary is the opening line's own answer
    and answers maps each stop's line index to the dates it occupies.

  * `{:error, :no_start_date}` when the opening line names no day to start on,
    which is the one fact a trip cannot be planned without.

  """
  @spec plan([Line.t()], non_neg_integer(), keyword()) ::
          {:ok, String.t() | nil, %{non_neg_integer() => String.t()}} | {:error, term()}
  def plan(document, index, options \\ []) do
    locale = Keyword.get_lazy(options, :locale, &Localize.get_locale/0)
    opening = Enum.at(document, index)
    block = block(document, index)

    case dates(opening, locale) do
      [] ->
        {:error, :no_start_date}

      [start | rest] ->
        budget = List.first(rest) || closing_date(block, locale)

        {answers, finish} = walk(block, start, locale)

        {:ok, summarise(start, finish, budget, locale), answers}
    end
  end

  # A trip runs to the next heading or the next trip, whichever comes first.
  # Two trips under one heading are two trips, and a heading ends the one above
  # it the way it ends the block a subtotal reaches over.
  defp block(document, index) do
    document
    |> Enum.drop(index + 1)
    |> Enum.take_while(&(&1.kind not in [:heading, :trip]))
  end

  # Each stop begins where the last one ended, so the walk carries the date
  # forward and every stop's answer is the interval it occupies. A stop with no
  # place or no count is passed over rather than guessed at.
  defp walk(block, start, locale) do
    Enum.reduce(block, {%{}, start}, fn line, {answers, cursor} ->
      case stop(line) do
        {:ok, nights, _place} ->
          finish = Date.add(cursor, nights)

          {Map.put(answers, line.index, interval(cursor, finish, locale)), finish}

        :error ->
          {closing_answer(answers, line, locale), cursor}
      end
    end)
  end

  # The closing line answers with the day it names, so a reader can see that
  # the sheet read the date they meant.
  defp closing_answer(answers, %Line{kind: :trip_end} = line, locale) do
    case dates(line, locale) do
      [date | _rest] -> Map.put(answers, line.index, day(date, locale))
      [] -> answers
    end
  end

  defp closing_answer(answers, _line, _locale), do: answers

  defp closing_date(block, locale) do
    block
    |> Enum.filter(&(&1.kind == :trip_end))
    |> Enum.flat_map(&dates(&1, locale))
    |> List.first()
  end

  # The dates a line names, in the order they are written, read by the same
  # tokenizer that reads every other date on the sheet. A trip therefore starts
  # on `March 3, 2026` in English and on `3.3.2026` in German without either
  # form being written down here.
  defp dates(%Line{} = line, locale) do
    with body when is_binary(body) <- trip_body(line),
         {:ok, tokens} <- Tokenizer.tokenize(body, locale: locale) do
      tokens
      |> Enum.filter(&(&1.kind == :temporal))
      |> Enum.map(&resolve(&1.value, locale))
      |> Enum.reject(&is_nil/1)
    else
      _unreadable -> []
    end
  end

  defp trip_body(%Line{kind: :trip, expression: body}) when is_binary(body) do
    case Regex.run(@opening, body) do
      [_whole, rest] -> rest
      nil -> body
    end
  end

  defp trip_body(%Line{kind: :trip_end, expression: body}) when is_binary(body) do
    case Regex.run(@ending, body) do
      [_whole, rest] -> rest
      nil -> body
    end
  end

  defp trip_body(%Line{}), do: nil

  defp resolve(fields, _locale) do
    with {:ok, tempo} <- Temporal.resolve(fields, []),
         {:ok, date} <- Tempo.to_date(tempo) do
      date
    else
      _not_a_day -> nil
    end
  end

  defp interval(from, to, locale) do
    case Localize.Interval.to_string(from, to, locale: locale, format: :medium) do
      {:ok, formatted} -> formatted
      {:error, _reason} -> nil
    end
  end

  defp day(date, locale) do
    case Localize.Date.to_string(date, locale: locale, format: :medium) do
      {:ok, formatted} -> formatted
      {:error, _reason} -> nil
    end
  end

  # The opening line's answer: how long the trip is, and — where a finishing
  # date was given — whether it fits. Nothing at all until there is a stop to
  # report on, because `0 nights` is a worse answer than a blank margin for a
  # trip somebody has only just started writing.
  defp summarise(start, finish, budget, locale) do
    case Date.diff(finish, start) do
      0 -> nil
      nights -> verdict(nights, budget && Date.diff(budget, start), locale)
    end
  end

  defp verdict(nights, nil, locale) do
    with_locale(locale, fn -> ~t"#{nights = number(nights, locale)} nights" end)
  end

  defp verdict(nights, available, locale) when nights < available do
    spare = number(available - nights, locale)

    with_locale(locale, fn ->
      ~t"#{nights = number(nights, locale)} nights, #{spare = spare} to spare"
    end)
  end

  defp verdict(nights, available, locale) when nights > available do
    over = number(nights - available, locale)

    with_locale(locale, fn ->
      ~t"#{nights = number(nights, locale)} nights, #{over = over} over"
    end)
  end

  defp verdict(nights, _exact, locale) do
    with_locale(locale, fn -> ~t"#{nights = number(nights, locale)} nights, exactly" end)
  end

  # Formatted before it reaches the message, so the message cannot format it a
  # second time in whatever locale Gettext happened to resolve. The same reason
  # `LocalizePad.Value` does it for a set's count.
  defp number(count, locale) do
    case Localize.Number.to_string(count, locale: locale) do
      {:ok, formatted} -> formatted
      {:error, _reason} -> to_string(count)
    end
  end

  defp with_locale(locale, fun) do
    Gettext.with_locale(LocalizePad.Gettext, gettext_locale(locale), fun)
  end

  defp gettext_locale(locale) do
    case Localize.validate_locale(locale) do
      {:ok, language_tag} -> to_string(language_tag.language)
      {:error, _reason} -> "en"
    end
  end
end
