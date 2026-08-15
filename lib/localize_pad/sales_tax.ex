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

  ## Configuration

      config :localize_pad, sales_tax: [name: "VAT", rate: 15]

  There is no correct default. Rates vary by country and, in the United
  States, by state — which is why Soulver asks its American users to set it
  themselves rather than guessing from geolocation.

  """

  alias LocalizePad.Percentage

  defstruct [:name, :rate]

  @type t :: %__MODULE__{name: String.t(), rate: Percentage.t()}

  @default_name "VAT"
  @default_rate 0

  @doc """
  Returns the configured sales tax.

  ### Returns

  * A `t:LocalizePad.SalesTax.t/0`. With nothing configured the rate is zero,
    so tax phrases evaluate to a no-op rather than failing — a sheet written
    before the rate was set still reads sensibly.

  ### Examples

      iex> LocalizePad.SalesTax.configured().name
      "VAT"

  """
  @spec configured() :: t()
  def configured do
    settings = Application.get_env(:localize_pad, :sales_tax, [])

    %__MODULE__{
      name: Keyword.get(settings, :name, @default_name),
      rate: Percentage.new(Keyword.get(settings, :rate, @default_rate))
    }
  end

  @doc """
  Whether a word names the configured sales tax.

  ### Arguments

  * `word` - the word to test.

  ### Returns

  * `true` or `false`.

  ### Examples

      iex> LocalizePad.SalesTax.names_tax?("VAT")
      true

      iex> LocalizePad.SalesTax.names_tax?("breakfast")
      false

  """
  @spec names_tax?(String.t()) :: boolean()
  def names_tax?(word) when is_binary(word) do
    downcased = String.downcase(word)

    downcased in ["vat", "gst", "sales tax"] or
      downcased == String.downcase(configured().name)
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
  def gross_multiplier(%__MODULE__{rate: rate}) do
    1 + Percentage.to_decimal(rate)
  end
end
