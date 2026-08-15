defmodule LocalizePad.Percentage do
  @moduledoc """
  A percentage, which is not simply a number divided by a hundred.

  ## Why this needs its own type

  A percentage behaves differently depending on what it sits next to, and that
  contextual behaviour is the single most-praised thing about a notepad
  calculator. `200 + 10%` is 220, because the percentage is *of* the thing on
  its left. But `10% + 20%` is 30%, because there is nothing to be a percentage
  of. And `50% × 30` is 15 — a plain number, because multiplying by a
  percentage is just multiplying.

  A `Decimal` cannot express that. Neither can a tagged number without the
  arithmetic table that goes with it, which is why the whole table lives in
  `LocalizePad.Evaluator` and this module stays deliberately small.

  ## The table

  | Expression | Answer | Rule |
  |---|---|---|
  | `200 + 10%` | `220` | relative to the left operand |
  | `200 - 10%` | `180` | ditto |
  | `10% + 20%` | `30%` | percent and percent stays percent |
  | `30% + 0.4` | `70%` | a bare number is coerced, 1.0 being 100% |
  | `50% × 30` | `15` | multiplication always yields a number |
  | `30 × 50%` | `15` | order-independent |
  | `10% of 200` | `20` | phrase form |
  | `10% off 200` | `180` | phrase form |
  | `10% on 200` | `220` | phrase form |

  """

  defstruct [:value]

  @type t :: %__MODULE__{value: number()}

  @doc """
  Builds a percentage from its face value — `10` for 10%, not `0.1`.

  ### Arguments

  * `value` - the percentage as written.

  ### Returns

  * A `t:LocalizePad.Percentage.t/0`.

  ### Examples

      iex> LocalizePad.Percentage.new(10)
      %LocalizePad.Percentage{value: 10}

  """
  @spec new(number()) :: t()
  def new(value) when is_number(value), do: %__MODULE__{value: value}

  @doc """
  Returns the percentage as a plain multiplier — 10% becomes 0.1.

  ### Arguments

  * `percentage` - the percentage to convert.

  ### Returns

  * A float.

  ### Examples

      iex> 20 |> LocalizePad.Percentage.new() |> LocalizePad.Percentage.to_decimal()
      0.2

  """
  @spec to_decimal(t()) :: float()
  def to_decimal(%__MODULE__{value: value}), do: value / 100

  @doc """
  Coerces a bare number into a percentage, treating 1.0 as 100%.

  This is what makes `30% + 0.4` come to 70% rather than 30.4%: in the
  company of a percentage, a bare number is read as a proportion.

  ### Arguments

  * `value` - a number or an existing percentage.

  ### Returns

  * A `t:LocalizePad.Percentage.t/0`.

  ### Examples

      iex> LocalizePad.Percentage.coerce(0.4)
      %LocalizePad.Percentage{value: 40.0}

      iex> LocalizePad.Percentage.coerce(LocalizePad.Percentage.new(30))
      %LocalizePad.Percentage{value: 30}

  """
  @spec coerce(number() | t()) :: t()
  def coerce(%__MODULE__{} = percentage), do: percentage
  def coerce(value) when is_number(value), do: new(value * 100)

  @doc """
  Applies the percentage to a value, returning the portion it represents.

  ### Arguments

  * `percentage` - the percentage.

  * `value` - the number the percentage is of.

  ### Returns

  * The portion, as a float.

  ### Examples

      iex> 10 |> LocalizePad.Percentage.new() |> LocalizePad.Percentage.of(200)
      20.0

  """
  @spec of(t(), number()) :: float()
  def of(%__MODULE__{} = percentage, value) when is_number(value) do
    value * to_decimal(percentage)
  end

  @doc """
  Formats a percentage in the given locale.

  ### Arguments

  * `percentage` - the percentage to format.

  * `options` - a keyword list of options.

  ### Options

  * `:locale` - the locale to format in. Defaults to `Localize.get_locale/0`.

  ### Returns

  * `{:ok, string}` on success, or `{:error, reason}`.

  ### Examples

      iex> LocalizePad.Percentage.format(LocalizePad.Percentage.new(10), locale: :en)
      {:ok, "10%"}

      iex> LocalizePad.Percentage.format(LocalizePad.Percentage.new(10), locale: :de)
      {:ok, "10\u00A0%"}

  """
  @spec format(t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def format(%__MODULE__{value: value}, options \\ []) do
    locale = Keyword.get_lazy(options, :locale, &Localize.get_locale/0)

    # CLDR knows where the percent sign goes and whether a space precedes it —
    # German writes `10 %` with a non-breaking space, English `10%`. Dividing
    # by a hundred here is what `:percent` formatting expects as input.
    Localize.Number.to_string(value / 100,
      locale: locale,
      format: :percent,
      max_fractional_digits: 6
    )
  end
end
