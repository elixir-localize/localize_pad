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

  ## In the reader's language, both halves

      Reise ab 3.3.2026            voyage du 3 mars 2026
      3 Nächte in Tokio            3 nuits à Tokyo
      Reise endet 22.3.2026        voyage fin 22 mars 2026

  The words that make a trip — the opening noun, the words that close one, the
  units a stay is counted in and the preposition that puts it somewhere — are
  per language and live in `LocalizePad.Lexicon`. Each language reads its own
  and no other's, as the totalling words do.

  The answers are the reader's too, and none of their spelling is written down
  here: the dates come back as a CLDR date interval, so a German sheet reads
  `03.03.2026 – 06.03.2026`, a French one `3–6 mars 2026` and a Japanese one
  `2026/03/03～2026/03/06`, while the count of nights comes from the message
  catalogue with that language's own plural rule.

  """

  use Localize.Message.Sigils,
    backend: LocalizePad.Gettext,
    sigils: [domain: "answers"]

  alias LocalizePad.{Lexicon, Line, Locales, Temporal, Tokenizer}

  @doc """
  Classifies a line as part of a trip, by shape alone.

  ### Arguments

  * `body` - the line's text, with any comment and tags already taken off.

  * `locale` - the locale whose trip vocabulary to read.

  ### Returns

  * `{:ok, :trip}` for the line that opens one, `{:ok, :trip_end}` for the line
    that closes one, and `{:ok, :trip_stop}` for a stop that names its place
    outright.

  * `:error` for everything else, which is nearly every line.

  ### Examples

      iex> LocalizePad.Trip.classify("trip from March 3, 2026", :en)
      {:ok, :trip}

      iex> LocalizePad.Trip.classify("trip ends March 22, 2026", :en)
      {:ok, :trip_end}

      iex> LocalizePad.Trip.classify("Reise ab 3. März 2026", :de)
      {:ok, :trip}

      iex> LocalizePad.Trip.classify("3 nights in Tokyo", :en)
      {:ok, :trip_stop}

      iex> LocalizePad.Trip.classify("3 nuits à Paris", :fr)
      {:ok, :trip_stop}

      iex> LocalizePad.Trip.classify("Tokyo: 3 nights", :en)
      :error

  """
  @spec classify(String.t(), Locales.locale()) :: {:ok, :trip | :trip_end | :trip_stop} | :error
  def classify(body, locale \\ :en) when is_binary(body) do
    words = words(body)
    vocabulary = Lexicon.trip(locale)

    cond do
      not opens?(words, vocabulary) -> stop_shaped(body, vocabulary)
      Enum.any?(words, &(&1 in vocabulary.ends)) -> {:ok, :trip_end}
      true -> {:ok, :trip}
    end
  end

  # The opening noun leads the line. `Reise ab 3. März` and `voyage du 3 mars`
  # both start with it, and a line merely *mentioning* a trip does not open one.
  defp opens?([first | _rest], vocabulary), do: first in vocabulary.opens
  defp opens?([], _vocabulary), do: false

  # Only the spelling that names its place outright is claimed at
  # classification time. `Tokyo: 3 nights` and `東京に3泊` are stops too, but
  # only in the company of a trip — claiming them everywhere would change what
  # an ordinary labelled line means on a sheet that has no itinerary on it.
  defp stop_shaped(body, vocabulary) do
    case forward(body, vocabulary) do
      {:ok, _nights, _place} -> {:ok, :trip_stop}
      :error -> :error
    end
  end

  @doc """
  Reads a line as a stop, in any of its spellings.

  ### Arguments

  * `line` - a classified line.

  * `locale` - the locale whose trip vocabulary to read.

  ### Returns

  * `{:ok, nights, place}` where nights is the number of days the stop
    occupies.

  * `:error` when the line is not a stop.

  ### Examples

      iex> LocalizePad.Trip.stop(LocalizePad.Line.classify(0, "3 nights in Tokyo"), :en)
      {:ok, 3, "Tokyo"}

      iex> LocalizePad.Trip.stop(LocalizePad.Line.classify(0, "Kyoto: 5 nights"), :en)
      {:ok, 5, "Kyoto"}

      iex> LocalizePad.Trip.stop(LocalizePad.Line.classify(0, "19 + 22"), :en)
      :error

  """
  @spec stop(Line.t(), Locales.locale()) :: {:ok, pos_integer(), String.t()} | :error
  def stop(line, locale \\ :en)

  def stop(%Line{kind: :trip_stop, expression: body}, locale) do
    forward(body, Lexicon.trip(locale))
  end

  # The label spelling, and the one that puts the place first. Both are read
  # only here, which is only ever called from inside a trip block.
  #
  # Place-first is how Japanese writes it — `東京に3泊`, the particle following
  # what it marks — and it is accepted in every language because `Tokyo 3
  # nights` is a natural thing to type in any of them. It could not be claimed
  # at classification time for exactly that reason: `coffee 3 days` has the
  # same shape and is an ordinary line.
  def stop(%Line{kind: :expression, label: place, expression: body}, locale)
      when is_binary(place) and is_binary(body) do
    case counted(String.trim(body), Lexicon.trip(locale)) do
      {:ok, nights} -> {:ok, nights, place}
      :error -> :error
    end
  end

  def stop(%Line{kind: :expression, expression: body}, locale) when is_binary(body) do
    reversed(body, Lexicon.trip(locale))
  end

  def stop(%Line{}, _locale), do: :error

  # `3 nights in Tokyo`, `3 nuits à Paris`, `3 Nächte in Tokio`.
  #
  # The place-marking word is required, not optional, and that is what keeps
  # this shape from swallowing ordinary lines: `28 days before March 12` and
  # `3 jours ouvrables après le 24 décembre` are a count and a unit followed by
  # words too, and neither is a stop. Both were read as one until the word was
  # made mandatory.
  #
  # The place keeps the case it was written in — it is a proper noun on its way
  # to the zone table, not a word to be matched.
  defp forward(body, vocabulary) do
    written = body |> String.trim() |> String.split(" ", trim: true)
    lowered = Enum.map(written, &String.downcase/1)

    with [count, stay, at | place] when place != [] <- lowered,
         {nights, ""} <- Integer.parse(count),
         true <- stay in vocabulary.stays,
         true <- at in vocabulary.at do
      {:ok, nights, written |> Enum.drop(3) |> Enum.join(" ")}
    else
      _not_a_stop -> :error
    end
  end

  # `東京に3泊`, `Tokyo 3 nights`.
  defp reversed(body, vocabulary) do
    trimmed = String.trim(body)

    Enum.find_value(vocabulary.stays, :error, fn stay ->
      with true <- String.ends_with?(String.downcase(trimmed), stay),
           head <- String.slice(trimmed, 0, String.length(trimmed) - String.length(stay)),
           {place, count} <- split_count(head),
           true <- place != "" do
        {:ok, count, place}
      else
        _no -> nil
      end
    end)
  end

  # The digits at the end of what is left, and the place before them, with any
  # place-marking particle taken off.
  defp split_count(head) do
    case Regex.run(~r/^(.*?)[\s]*(\d+)$/u, String.trim(head)) do
      [_whole, place, count] -> {String.trim(place), String.to_integer(count)}
      nil -> nil
    end
  end

  # `3 nights`, `3泊` — a count and a unit, and nothing else.
  defp counted(body, vocabulary) do
    Enum.find_value(vocabulary.stays, :error, fn stay ->
      case Regex.run(~r/^(\d+)\s*#{Regex.escape(stay)}$/iu, body) do
        [_whole, count] -> {:ok, String.to_integer(count)}
        nil -> nil
      end
    end)
  end

  defp words(body) do
    body
    |> String.trim()
    |> String.trim_trailing(":")
    |> String.downcase()
    |> String.split([" ", ":"], trim: true)
  end

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
      case stop(line, locale) do
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
  #
  # The whole line goes to the tokenizer, opening noun and all: `trip`, `Reise`
  # and `ends` are dates in no language, so there is nothing to strip — and
  # stripping would be a second place that has to agree about what the opening
  # words are.
  defp dates(%Line{expression: body}, locale) when is_binary(body) do
    {:ok, tokens} = Tokenizer.tokenize(body, locale: locale)

    tokens
    |> Enum.filter(&(&1.kind == :temporal))
    |> Enum.map(&resolve(&1.value, locale))
    |> Enum.reject(&is_nil/1)
  end

  defp dates(%Line{}, _locale), do: []

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
