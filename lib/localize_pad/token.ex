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
          :number | :word | :unit | :keyword | :operator | :punctuation | :line_ref | :temporal

  @type t :: %__MODULE__{
          kind: kind(),
          value: term(),
          source: String.t(),
          alternatives: keyword()
        }

  defstruct [:kind, :value, :source, alternatives: []]

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

      iex> LocalizePad.Token.new(:number, 3, "3")
      %LocalizePad.Token{kind: :number, value: 3, source: "3", alternatives: []}

      iex> LocalizePad.Token.new(:keyword, :to, "in", unit: "inch")
      %LocalizePad.Token{kind: :keyword, value: :to, source: "in", alternatives: [unit: "inch"]}

  """
  @spec new(kind(), term(), String.t(), keyword()) :: t()
  def new(kind, value, source, alternatives \\ []) do
    %__MODULE__{kind: kind, value: value, source: source, alternatives: alternatives}
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
end
