defmodule LocalizePad.Temporal.Uncertain do
  @moduledoc """
  Dates that are not precise: `the 1560s`, `circa 600 BCE`, `1984?`.

  ## Why a notepad should care

  Historians, archaeologists and archivists write dates like this constantly,
  and every calculator makes them convert to something precise first — which
  is exactly the information they are trying not to assert. ISO 8601-2 has
  standardised the notation and Tempo implements the whole of it, so a decade
  or an approximation can be a *value* here rather than a note in the margin.

  ## Phrases in, ISO 8601-2 out

  As with recurrence, nothing is implemented here. `the 1560s` becomes the
  masked year `156X`, `circa 600 BCE` becomes `-0600~`, and Tempo does the
  rest.

  ## They explain themselves

  A masked year has no single date to display, so these render through
  `Tempo.explain/1` — "A masked year spanning the 1560s" — which is more
  useful than any date could be, and is exactly the affordance §9 wanted for
  "why did I get this answer".

  """

  alias LocalizePad.Token

  @approximate ~w(circa about approximately around)
  @before_era ~w(bce bc)

  @doc """
  The words this module had to be told.

  TEMPORARY, for a demo — see `LocalizePad.Lexicon.authored/1`.

  ### Returns

  * A list of lowercased forms.

  ### Examples

      iex> "circa" in LocalizePad.Temporal.Uncertain.authored()
      true

  """
  @spec authored() :: [String.t()]
  def authored, do: @approximate ++ @before_era

  @doc """
  Recognises an imprecise date.

  ### Arguments

  * `tokens` - the tokens for one line.

  ### Returns

  * `{:ok, {:uncertain, iso}}` where `iso` is an ISO 8601-2 string.

  * `:error` when the line names no imprecise date.

  ### Examples

      iex> {:ok, tokens} = LocalizePad.Tokenizer.tokenize("the 1560s", locale: :en)
      iex> LocalizePad.Temporal.Uncertain.match(tokens)
      {:ok, {:uncertain, "156X"}}

      iex> {:ok, tokens} = LocalizePad.Tokenizer.tokenize("circa 600 BCE", locale: :en)
      iex> LocalizePad.Temporal.Uncertain.match(tokens)
      {:ok, {:uncertain, "-0600~"}}

  """
  @spec match([Token.t()]) :: {:ok, {:uncertain, String.t()}} | :error
  def match(tokens) when is_list(tokens) do
    words = Enum.map(tokens, &String.downcase(&1.source))

    cond do
      decade = find_decade(tokens, words) -> {:ok, {:uncertain, decade}}
      qualified = find_qualified(tokens, words) -> {:ok, {:uncertain, qualified}}
      true -> :error
    end
  end

  # `the 1560s`. The number scanner takes the digits and leaves a bare `s`,
  # which is the marker.
  defp find_decade(tokens, _words) do
    tokens
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.find_value(fn
      # The trailing `s` may arrive classified as a unit rather than a word —
      # `s` is the CLDR abbreviation for `second` — so accept either.
      [%Token{kind: kind, value: year}, %Token{kind: follower, source: "s"}]
      when kind == :number and follower in [:word, :unit] and is_integer(year) and
             year >= 1000 and rem(year, 10) == 0 ->
        "#{div(year, 10)}X"

      _other ->
        nil
    end)
  end

  # `circa 600 BCE`, `1984?`. An era marker makes the year negative; an
  # approximation marker adds ISO 8601-2's `~`.
  defp find_qualified(tokens, words) do
    approximate? = Enum.any?(words, &(&1 in @approximate))
    before_era? = Enum.any?(words, &(&1 in @before_era))

    with true <- approximate? or before_era?,
         year when is_integer(year) <- find_year(tokens) do
      sign = if before_era?, do: "-", else: ""
      qualifier = if approximate?, do: "~", else: ""

      "#{sign}#{pad(year)}#{qualifier}"
    else
      _no_year -> nil
    end
  end

  defp find_year(tokens) do
    Enum.find_value(tokens, fn token ->
      if token.kind == :number and is_integer(token.value) and token.value > 0, do: token.value
    end)
  end

  # ISO 8601 wants four digits, so a year before 1000 is padded.
  defp pad(year), do: year |> Integer.to_string() |> String.pad_leading(4, "0")

  @doc """
  Builds the value an imprecise date names.

  ### Arguments

  * `iso` - an ISO 8601-2 string from `match/1`.

  ### Returns

  * `{:ok, tempo}` on success, or `{:error, reason}`.

  """
  @spec resolve(String.t()) :: {:ok, Tempo.t()} | {:error, term()}
  def resolve(iso) when is_binary(iso) do
    Tempo.from_iso8601(iso)
  rescue
    exception -> {:error, exception}
  end

  @doc """
  Describes an imprecise value in words.

  A masked year has no single date to show, so it says what it is instead.

  ### Arguments

  * `tempo` - the value to describe.

  ### Returns

  * `{:ok, string}` on success, or `{:error, reason}`.

  """
  @spec explain(Tempo.t()) :: {:ok, String.t()} | {:error, term()}
  def explain(%Tempo{} = tempo) do
    # `explain/1` returns several lines, the last two of which tell a developer
    # how to iterate and materialise the value. A margin wants the headline;
    # the qualification is read from the struct rather than from Tempo's prose,
    # which is written for a terminal and not to be parsed.
    headline =
      tempo
      |> Tempo.explain()
      |> to_string()
      |> String.split("\n", trim: true)
      |> List.first()

    {:ok, headline <> qualifier(tempo)}
  rescue
    exception -> {:error, exception}
  end

  defp qualifier(%Tempo{qualification: :approximate}), do: " Approximate."
  defp qualifier(%Tempo{qualification: :uncertain}), do: " Uncertain."

  defp qualifier(%Tempo{qualification: :uncertain_and_approximate}),
    do: " Uncertain and approximate."

  defp qualifier(_tempo), do: ""
end
