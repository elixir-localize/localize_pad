defmodule LocalizePad.Token do
  @moduledoc """
  A single lexical item produced by `LocalizePad.Tokenizer`.

  A token carries its primary reading in `:kind` and `:value`, the exact source
  text it came from, and — importantly — any *alternative* readings in
  `:alternatives`.

  Alternatives exist because this language is genuinely ambiguous and the
  ambiguity cannot be resolved lexically. The clearest case is `in`: it is the
  conversion keyword in `100 celsius in fahrenheit` and the unit `inch` in
  `3 in`. A tokenizer that commits to one reading breaks the other, so the
  tokenizer reports both and `LocalizePad.Parser` chooses by position — keyword
  where an operator is expected, unit where an operand is expected.

  """

  @type kind ::
          :number
          | :word
          | :unit
          | :keyword
          | :operator
          | :punctuation
          | :line_ref
          | :temporal
          | :zone
          | :percentage
          | :money
          | :currency
          | :tax
          | :ordinal
          | :calendar

  @type t :: %__MODULE__{
          kind: kind(),
          value: term(),
          source: String.t(),
          alternatives: keyword(),
          start: non_neg_integer() | nil,
          length: non_neg_integer() | nil
        }

  defstruct [:kind, :value, :source, :start, :length, alternatives: []]

  @doc """
  Builds a token.

  ### Arguments

  * `kind` - the primary classification of the token.

  * `value` - the token's semantic value. For `:number` this is the parsed
    number, for `:unit` the resolved CLDR unit name, for `:keyword` the role
    atom, and for `:operator` the operator atom.

  * `source` - the exact text the token was read from.

  * `alternatives` - a keyword list of other readings, keyed by kind. Defaults
    to `[]`.

  ### Returns

  * A `t:LocalizePad.Token.t/0`.

  ### Examples

      iex> token = LocalizePad.Token.new(:number, 3, "3")
      iex> {token.kind, token.value, token.source}
      {:number, 3, "3"}

      iex> token = LocalizePad.Token.new(:keyword, :to, "in", unit: "inch")
      iex> token.alternatives
      [unit: "inch"]

  """
  @spec new(kind(), term(), String.t(), keyword()) :: t()
  def new(kind, value, source, alternatives \\ []) do
    %__MODULE__{kind: kind, value: value, source: source, alternatives: alternatives}
  end

  @doc """
  Records where in the line a token was read from.

  Spans are what an editor decorates with: highlighting, hover-to-peek, and
  click-an-answer-to-reference all need to map a character position back to the
  token that covers it. They are measured in bytes, matching Elixir's binary
  functions and the `Range` a browser's text APIs want.

  ### Arguments

  * `token` - the token to place.

  * `start` - the byte offset the token begins at.

  * `length` - how many bytes it covers.

  ### Returns

  * The token with its span recorded.

  ### Examples

      iex> token = :number |> LocalizePad.Token.new(2, "02") |> LocalizePad.Token.at(4, 2)
      iex> {token.start, token.length}
      {4, 2}

  """
  @spec at(t(), non_neg_integer(), non_neg_integer()) :: t()
  def at(%__MODULE__{} = token, start, length) do
    %{token | start: start, length: length}
  end

  @doc """
  Gives a token the span covered by the tokens it was built from.

  Several passes replace a run of tokens with one — `@` and `3` become a line
  reference, `20` and `%` a percentage. The replacement covers everything the
  run did, which is what an editor needs in order to highlight `@3` as one
  thing rather than two.

  ### Arguments

  * `token` - the combined token.

  * `covering` - the tokens it was built from, in source order.

  ### Returns

  * The token spanning from the first covered token to the last. A token built
    from nothing placed is returned unchanged, so a caller need not check.

  ### Examples

      iex> at = LocalizePad.Token.new(:word, "@", "@") |> LocalizePad.Token.at(0, 1)
      iex> three = LocalizePad.Token.new(:number, 3, "3") |> LocalizePad.Token.at(1, 1)
      iex> reference = LocalizePad.Token.new(:line_ref, 3, "@3")
      iex> token = LocalizePad.Token.covering(reference, [at, three])
      iex> {token.start, token.length}
      {0, 2}

  """
  @spec covering(t(), [t()]) :: t()
  def covering(%__MODULE__{} = token, covering) do
    placed = Enum.filter(covering, &(&1.start != nil and &1.length != nil))

    case placed do
      [] ->
        token

      tokens ->
        start = tokens |> Enum.map(& &1.start) |> Enum.min()
        finish = tokens |> Enum.map(&(&1.start + &1.length)) |> Enum.max()

        at(token, start, finish - start)
    end
  end

  @doc """
  Returns the token's value under an alternative reading.

  ### Arguments

  * `token` - the token to read.

  * `kind` - the alternative kind to look for.

  ### Returns

  * `{:ok, value}` when the token can be read as `kind`, either because that is
    its primary kind or because it appears in `:alternatives`.

  * `:error` when the token has no such reading.

  ### Examples

      iex> token = LocalizePad.Token.new(:keyword, :to, "in", unit: "inch")
      iex> LocalizePad.Token.as(token, :unit)
      {:ok, "inch"}

      iex> token = LocalizePad.Token.new(:keyword, :to, "to")
      iex> LocalizePad.Token.as(token, :unit)
      :error

  """
  @spec as(t(), kind()) :: {:ok, term()} | :error
  def as(%__MODULE__{kind: kind, value: value}, kind), do: {:ok, value}

  def as(%__MODULE__{alternatives: alternatives}, kind) do
    Keyword.fetch(alternatives, kind)
  end

  @doc """
  Returns whether the token can be read as `kind`.

  ### Arguments

  * `token` - the token to test.

  * `kind` - the kind to test for.

  ### Returns

  * `true` or `false`.

  ### Examples

      iex> token = LocalizePad.Token.new(:keyword, :to, "in", unit: "inch")
      iex> LocalizePad.Token.is?(token, :unit)
      true

  """
  @spec is?(t(), kind()) :: boolean()
  def is?(token, kind) do
    match?({:ok, _value}, as(token, kind))
  end

  @doc """
  Turns a keyword that also names a unit back into an ordinary word.

  `in` carries both readings because nothing before evaluation can tell them
  apart: `12 ft + 3 in` is inches and `19 + 22 in cash` is not, and the two are
  the same shape. Only the units failing to agree reveals which it was, and
  demoting is how that discovery is fed back — the word becomes prose, to be
  skipped like any other, rather than falling through to its *other* operator
  reading and turning `in cash` into a conversion with nothing to convert to.

  Every other token is returned unchanged, so a caller can map this over a
  whole line and compare the result to know whether anything was ambiguous.

  ### Arguments

  * `token` - the token to demote.

  ### Returns

  * An inert `:word` token when the token was an ambiguous keyword, and the
    token itself otherwise.

  ### Examples

      iex> token = LocalizePad.Token.new(:keyword, :to, "in", unit: "inch")
      iex> LocalizePad.Token.demote(token).kind
      :word

      iex> token = LocalizePad.Token.new(:keyword, :per, "per")
      iex> LocalizePad.Token.demote(token) == token
      true

  """
  @spec demote(t()) :: t()
  def demote(%__MODULE__{kind: :keyword, source: source} = token) do
    if is?(token, :unit) do
      %{token | kind: :word, value: source, alternatives: []}
    else
      token
    end
  end

  def demote(%__MODULE__{} = token), do: token
end
