defmodule LocalizePad.SalesTax do
  @moduledoc """
  VAT, GST, sales tax — a percentage that does not behave like one.

  ## Why this is not just a `LocalizePad.Percentage`

  Taking tax *off* a price is not subtracting a percentage. A gross price of
  £300 that includes 15% VAT had a net price of £260.87, because £300 is
  115% of the net — so the operation is division by 1.15, not subtraction of
  15%. Subtracting would give £255, which is wrong by £5.87 and wrong in a way
  nobody notices until an invoice disagrees.

  That single asymmetry is why sales tax is its own type. Everything else
  follows from which side of the phrase the tax appears on:

  | Phrase | Answer at 15% | Meaning |
  |---|---|---|
  | `$300 + VAT` | `$345.00` | add tax to a net price |
  | `$300 - VAT` | `$260.87` | recover the net price from a gross one |
  | `VAT on $300` | `$45.00` | the tax a net price attracts |
  | `VAT off $300` | `$260.87` | the net price inside a gross one |
  | `VAT of $300` | `$39.13` | the tax already inside a gross price |

  Note that `VAT on $300` and `VAT of $300` differ: the first treats $300 as
  net, the second as gross. Both readings are in use, and Soulver documents
  both, so the preposition has to carry the distinction.

  ## The rate is declared in the sheet

      VAT = 25%
      VAT on $300

  There is no default rate and no configured one. Rates vary by country and,
  in the United States, by state, so any value the app picked would be wrong
  for most people — and wrong silently, since `$0.00` reads like an answer
  rather than like a missing setting.

  Nor does the rate belong in application config, which would make the same
  sheet mean different things on different deployments. A pad is shared by
  URL and opened by somebody else; it has to carry everything its answers
  depend on. Until a line declares the rate, tax phrases refuse.

  """

  alias LocalizePad.{Lexicon, Locales}

  alias LocalizePad.Percentage

  defstruct [:name, :rate]

  @type t :: %__MODULE__{name: String.t(), rate: Percentage.t() | nil}

  @doc """
  Returns the tax a word names, with no rate until the sheet declares one.

  ### Arguments

  * `word` - the word naming the tax, as written.

  ### Returns

  * A `t:LocalizePad.SalesTax.t/0` whose `:rate` is `nil`.

  ### Examples

      iex> LocalizePad.SalesTax.named("VAT")
      %LocalizePad.SalesTax{name: "VAT", rate: nil}

  """
  @spec named(String.t()) :: t()
  def named(word) when is_binary(word) do
    %__MODULE__{name: word, rate: nil}
  end

  @doc """
  Whether a word names a sales tax.

  ### Arguments

  * `word` - the word to test.

  * `locale` - the locale whose vocabulary to read.

  ### Returns

  * `true` or `false`.

  ### Examples

      iex> LocalizePad.SalesTax.names_tax?("VAT")
      true

      iex> LocalizePad.SalesTax.names_tax?("MwSt", :de)
      true

      iex> LocalizePad.SalesTax.names_tax?("breakfast")
      false

  """
  @spec names_tax?(String.t(), Locales.locale()) :: boolean()
  def names_tax?(word, locale \\ :en) when is_binary(word) do
    Lexicon.tax?(word, locale)
  end

  @doc """
  The multiplier a net price is scaled by to include tax — 1.15 at 15%.

  ### Arguments

  * `tax` - the sales tax.

  ### Returns

  * A number.

  ### Examples

      iex> LocalizePad.SalesTax.gross_multiplier(%LocalizePad.SalesTax{
      ...>   name: "VAT",
      ...>   rate: LocalizePad.Percentage.new(15)
      ...> })
      1.15

  """
  @spec gross_multiplier(t()) :: float()
  def gross_multiplier(%__MODULE__{rate: %Percentage{} = rate}) do
    1 + Percentage.to_decimal(rate)
  end
end
