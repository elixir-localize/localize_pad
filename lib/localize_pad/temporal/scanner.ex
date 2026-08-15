defmodule LocalizePad.Temporal.Scanner do
  @moduledoc """
  Finds date and time spans in a line before the number scanner sees it.

  ## Why this runs first, on raw text

  `Calendrical.parse/2` is whole-string anchored, so it cannot be handed a
  whole notepad line. It has to be offered *candidate windows* — runs of
  consecutive words — and asked whether each one is a date.

  Those windows are cut from the original text rather than reassembled from
  tokens, because a token cannot reproduce the text it came from: the number
  scanner turns `02` into `2`, and `12/02/1988` rebuilt from tokens is
  `12/2/1988`. That happens to still parse, but only by luck, and the luck runs
  out for zero-padded times and two-digit years.

  ## The shape filter is the whole safety mechanism

  `Calendrical.parse("2026", as: :map)` succeeds — it is a year. So does
  `parse("11")`. If every window were offered to the parser, `2026 + 1` would
  become a date plus one and `100/5` would become the first of May.

  So a window is only offered when it *looks* temporal: a clock colon, an
  am/pm marker, a month or weekday name, a digit-separator-digit date shape, or
  a quarter or week designator. A bare run of digits is a number, always. This
  is deliberately conservative — a missed date shows up as arithmetic that
  still works, whereas a false date silently changes an answer.

  ## Longest match wins

  Windows are tried longest-first from each position, so `Saturday, May 16,
  2026` is one date rather than a weekday followed by a different date.

  """

  # Longest candidate window, in words. `Saturday, May 16, 2026` is four;
  # `2nd quarter of 2026` is four. Six leaves room without making the scan
  # quadratic in practice.
  @maximum_window 6

  @clock_time ~r/\d\s*:\s*\d/u
  @day_period ~r/\d\s*(am|pm|a\.m\.|p\.m\.)\b/iu
  @quarter ~r/\bq[1-4]\b/iu

  # A separated date needs *two* separators, not one. A single one is
  # indistinguishable from ordinary arithmetic: `9.8` is a decimal in English
  # and `100/5` is a division, yet both would satisfy digit-separator-digit and
  # both parse as dates if offered. Requiring three number groups admits
  # `12/02/1988`, `16.05.2026` and `2026-06-15` while leaving decimals and
  # divisions alone.
  #
  # The cost is that a year-less numeric date — `3/4` — is not recognised.
  # That is the right trade: it is genuinely ambiguous with division, and
  # writing `3 April` costs the user nothing.
  @date_separated ~r/\d+\s*[\/.\-]\s*\d+\s*[\/.\-]\s*\d+/u

  @type segment :: {:text, String.t()} | {:temporal, map(), String.t()}

  @doc """
  Splits a line into ordinary text and recognised temporal spans.

  ### Arguments

  * `text` - the line to scan.

  * `options` - a keyword list of options.

  ### Options

  * `:locale` - the locale whose date patterns and month names apply. Defaults
    to `Localize.get_locale/0`.

  ### Returns

  * A list of segments in source order. `{:text, string}` is everything the
    scanner did not claim; `{:temporal, fields, source}` is a recognised span,
    where `fields` is the partial field map from `Calendrical.parse/2` — it may
    carry only a month and day, or only an hour.

  ### Examples

      iex> LocalizePad.Temporal.Scanner.scan("2 + 2", locale: :en)
      [{:text, "2 + 2"}]

      iex> [{:temporal, fields, "10 June"}] =
      ...>   LocalizePad.Temporal.Scanner.scan("10 June", locale: :en)
      iex> {fields[:month], fields[:day]}
      {6, 10}

  """
  @spec scan(String.t(), keyword()) :: [segment()]
  def scan(text, options \\ []) when is_binary(text) do
    locale = Keyword.get_lazy(options, :locale, &Localize.get_locale/0)
    words = word_spans(text)

    text
    |> claim(words, locale, [])
    |> merge_text(text)
  end

  # Walk the word list, trying the longest temporal window at each position.
  defp claim(_text, [], _locale, claimed), do: Enum.reverse(claimed)

  defp claim(text, [{start, _length} | later_words] = words, locale, claimed) do
    case longest_match(text, words, locale) do
      {:ok, fields, source, consumed} ->
        finish = start + byte_size(source)

        claim(text, Enum.drop(words, consumed), locale, [
          {:temporal, fields, source, start, finish} | claimed
        ])

      :error ->
        claim(text, later_words, locale, claimed)
    end
  end

  defp longest_match(text, words, locale) do
    available = min(@maximum_window, length(words))

    available..1//-1
    |> Enum.find_value(:error, fn window ->
      source = window_source(text, words, window)

      with true <- temporal_shape?(source, locale),
           {:ok, fields} when is_map(fields) <- parse(source, locale) do
        {:ok, fields, source, window}
      else
        _no_match -> nil
      end
    end)
  end

  defp window_source(text, words, window) do
    [{start, _length} | _rest] = words
    {last_start, last_length} = Enum.at(words, window - 1)

    binary_part(text, start, last_start + last_length - start)
  end

  # `as: :map` is what makes a partial date usable — `May 5` has no year, and
  # deciding which year it means is a policy question for the evaluator, not
  # something to have guessed here.
  defp parse(source, locale) do
    Calendrical.parse(source, locale: locale, as: :map)
  rescue
    # The parser is not supposed to raise, but this sits on the render path of
    # a live document and a malformed span must never take a sheet down.
    _exception -> :error
  end

  # A window is only worth offering to the parser if it looks like a date or a
  # time. See the moduledoc: this filter is what stops `2026 + 1` becoming a
  # date, and it errs towards refusing.
  defp temporal_shape?(source, locale) do
    Regex.match?(@clock_time, source) or
      Regex.match?(@day_period, source) or
      Regex.match?(@date_separated, source) or
      Regex.match?(@quarter, source) or
      names_a_month_or_weekday?(source, locale)
  end

  defp names_a_month_or_weekday?(source, locale) do
    downcased = String.downcase(source)

    locale
    |> calendar_names()
    |> Enum.any?(&String.contains?(downcased, &1))
  end

  # Month and weekday names come from CLDR, so this works in every locale
  # without a word of it being authored here. Abbreviated forms are included
  # so `10 Jun` is recognised as readily as `10 June`.
  defp calendar_names(locale) do
    key = {__MODULE__, :calendar_names, locale}

    case :persistent_term.get(key, nil) do
      nil ->
        names = build_calendar_names(locale)
        :persistent_term.put(key, names)
        names

      names ->
        names
    end
  end

  defp build_calendar_names(locale) do
    [
      names_from(Localize.Calendar.months(locale)),
      names_from(Localize.Calendar.days(locale))
    ]
    |> Enum.concat()
    |> Enum.map(&String.downcase/1)
    |> Enum.uniq()
    # Longest first so a containment test cannot match "Mar" inside "March"
    # and stop early on the shorter name.
    |> Enum.sort_by(&(-String.length(&1)))
  end

  defp names_from({:ok, %{format: format}}) do
    format
    |> Map.take([:wide, :abbreviated])
    |> Map.values()
    |> Enum.flat_map(&Map.values/1)
    # Narrow forms are single letters and would match almost any word, so they
    # are excluded from the widths taken above; anything else too short is
    # dropped here for the same reason.
    |> Enum.filter(&(is_binary(&1) and String.length(&1) >= 3))
  end

  defp names_from(_other), do: []

  # Rebuild the segment list, filling the gaps between claimed spans with the
  # original text so nothing is lost or reordered.
  defp merge_text(claims, text) do
    {segments, position} =
      Enum.reduce(claims, {[], 0}, fn {:temporal, fields, source, start, finish},
                                      {acc, position} ->
        acc = prepend_text(acc, binary_part(text, position, start - position))
        {[{:temporal, fields, source} | acc], finish}
      end)

    segments
    |> prepend_text(binary_part(text, position, byte_size(text) - position))
    |> Enum.reverse()
  end

  defp prepend_text(segments, ""), do: segments
  defp prepend_text(segments, text), do: [{:text, text} | segments]

  # Byte offsets and lengths of each whitespace-delimited word.
  defp word_spans(text) do
    ~r/\S+/u
    |> Regex.scan(text, return: :index)
    |> Enum.map(fn [span] -> span end)
  end
end
