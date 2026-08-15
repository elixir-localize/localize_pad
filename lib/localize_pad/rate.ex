defmodule LocalizePad.Rate do
  @moduledoc """
  Money per unit of something — `$99/week`, `€30/day`.

  ## Why only money needs this

  `Localize.Unit` already models a rate whose numerator is a quantity:
  `90 km / 3 day` is a `kilometer-per-day` and needs nothing from this module.
  It even gets the awkward case right — `3 hours / day` cancels to 0.125,
  because mathematically it must, which is the behaviour Soulver documents and
  then offers an escape from.

  What CLDR units cannot express is money over a unit, because money is not a
  unit. That is the whole of this type.

  ## The denominator is a quantity, not a name

  `:per` holds a one-unit quantity — one week, one day — rather than the string
  `"week"`. Keeping it as a `Localize.Unit` means the denominator carries its
  own dimension and conversion is mostly ordinary unit conversion.

  ## Months and years need a convention, and we supply it

  `Localize.Unit.convert/2` refuses `month → day` and `year → day`, and it is
  right to: a month has no fixed length, so there is no conversion, only a
  convention. `week → day`, `day → hour` and `year → month` all convert
  exactly and are allowed.

  But `$30/day in €/month` is a reasonable question with a conventional answer,
  and declining it would make rates useless for exactly the domain — pay,
  rent, subscriptions — where people reach for them. So the table below
  supplies the Gregorian mean: a year of 365.2425 days and a month of one
  twelfth of that, 30.436875 days.

  Two things about that table are deliberate. It is stated here rather than
  pushed into Localize, because it is an assumption this application makes and
  not a fact CLDR asserts. And it agrees exactly with the conversions Localize
  *does* allow — 7 days to the week, 24 hours to the day, 12 months to the
  year — so using it uniformly introduces no disagreement.

  """

  alias Localize.Unit

  defstruct [:amount, :per]

  @type t :: %__MODULE__{amount: Money.t(), per: Unit.t()}

  @doc """
  Builds a rate from an amount and the unit it is per.

  ### Arguments

  * `amount` - a `t:Money.t/0`.

  * `per` - a `t:Localize.Unit.t/0` giving the denominator. Its value is
    normalised to one, so `$99 per 2 weeks` becomes `$49.50 per week`.

  ### Returns

  * `{:ok, rate}` on success, or `{:error, reason}`.

  ### Examples

      iex> {:ok, week} = Localize.Unit.new(1, "week")
      iex> {:ok, rate} = LocalizePad.Rate.new(Money.new(:USD, 99), week)
      iex> rate.amount
      Money.new(:USD, 99)

  """
  @spec new(Money.t(), Unit.t()) :: {:ok, t()} | {:error, term()}
  def new(%Money{} = amount, %Unit{value: value} = per) when is_number(value) do
    with {:ok, scaled} <- scale(amount, value),
         {:ok, unit} <- Unit.new(1, per.name) do
      {:ok, %__MODULE__{amount: scaled, per: unit}}
    end
  end

  def new(_amount, per), do: {:error, {:not_a_rate_denominator, per}}

  # `$99 per 2 weeks` is $49.50 a week. Dividing by one is a no-op, so the
  # common case costs nothing.
  defp scale(amount, 1), do: {:ok, amount}
  defp scale(_amount, 0), do: {:error, :division_by_zero}
  defp scale(amount, value), do: Money.div(amount, value)

  @doc """
  Converts a rate to a different denominator.

  ### Arguments

  * `rate` - the rate to convert.

  * `target` - a `t:Localize.Unit.t/0` naming the new denominator.

  ### Returns

  * `{:ok, rate}` on success.

  * `{:error, reason}` when the denominators are not conformable — there is no
    sensible reading of dollars per week as dollars per kilogram.

  ### Examples

      iex> {:ok, day} = Localize.Unit.new(1, "day")
      iex> {:ok, week} = Localize.Unit.new(1, "week")
      iex> {:ok, rate} = LocalizePad.Rate.new(Money.new(:USD, 10), day)
      iex> {:ok, weekly} = LocalizePad.Rate.convert(rate, week)
      iex> weekly.amount
      Money.new(:USD, 70)

  """
  @spec convert(t(), Unit.t()) :: {:ok, t()} | {:error, term()}
  def convert(%__MODULE__{} = rate, %Unit{} = target) do
    # How many of the rate's own denominator fit into one of the target's.
    # A day into a week is seven, so $10/day is $70/week.
    with {:ok, factor} <- ratio(target.name, rate.per.name),
         {:ok, amount} <- Money.mult(rate.amount, factor) do
      new(amount, target)
    end
  end

  # Mean Gregorian lengths, in days. See the moduledoc on why these are stated
  # here rather than asked of Localize.
  @days_per %{
    "second" => 1 / 86_400,
    "minute" => 1 / 1_440,
    "hour" => 1 / 24,
    "day" => 1,
    "week" => 7,
    "month" => 365.2425 / 12,
    "year" => 365.2425
  }

  defp ratio(from, to) do
    case {Map.fetch(@days_per, from), Map.fetch(@days_per, to)} do
      {{:ok, from_days}, {:ok, to_days}} ->
        {:ok, from_days / to_days}

      _not_calendar_units ->
        with {:ok, converted} <- Unit.new(1, from),
             {:ok, in_target} <- Unit.convert(converted, to) do
          {:ok, in_target.value}
        end
    end
  end

  @doc """
  Multiplies a rate by a quantity of its denominator, giving an amount.

  ### Arguments

  * `rate` - the rate.

  * `quantity` - a `t:Localize.Unit.t/0` conformable with the denominator.

  ### Returns

  * `{:ok, money}` on success, or `{:error, reason}`.

  ### Examples

      iex> {:ok, week} = Localize.Unit.new(1, "week")
      iex> {:ok, rate} = LocalizePad.Rate.new(Money.new(:USD, 50), week)
      iex> {:ok, twelve_weeks} = Localize.Unit.new(12, "week")
      iex> LocalizePad.Rate.multiply(rate, twelve_weeks)
      {:ok, Money.new(:USD, 600)}

  """
  @spec multiply(t(), Unit.t()) :: {:ok, Money.t()} | {:error, term()}
  def multiply(%__MODULE__{} = rate, %Unit{value: value} = quantity) do
    with {:ok, factor} <- ratio(quantity.name, rate.per.name) do
      Money.mult(rate.amount, factor * value)
    end
  end

  @doc """
  Adds two rates, expressing the result in the left one's denominator.

  ### Arguments

  * `left`, `right` - the rates to add.

  ### Returns

  * `{:ok, rate}` on success, or `{:error, reason}`.

  ### Examples

      iex> {:ok, day} = Localize.Unit.new(1, "day")
      iex> {:ok, week} = Localize.Unit.new(1, "week")
      iex> {:ok, daily} = LocalizePad.Rate.new(Money.new(:USD, 1), day)
      iex> {:ok, weekly} = LocalizePad.Rate.new(Money.new(:USD, 7), week)
      iex> {:ok, sum} = LocalizePad.Rate.add(daily, weekly)
      iex> sum.amount
      Money.new(:USD, 2)

  """
  @spec add(t(), t()) :: {:ok, t()} | {:error, term()}
  def add(%__MODULE__{} = left, %__MODULE__{} = right) do
    with {:ok, aligned} <- convert(right, left.per),
         {:ok, amount} <- Money.add(left.amount, aligned.amount) do
      {:ok, %__MODULE__{left | amount: amount}}
    end
  end

  @doc """
  Formats a rate in the given locale.

  ### Arguments

  * `rate` - the rate to format.

  * `options` - a keyword list of options.

  ### Options

  * `:locale` - the locale to format in. Defaults to `Localize.get_locale/0`.

  ### Returns

  * `{:ok, string}` on success, or `{:error, reason}`.

  ### Examples

      iex> {:ok, week} = Localize.Unit.new(1, "week")
      iex> {:ok, rate} = LocalizePad.Rate.new(Money.new(:USD, 99), week)
      iex> LocalizePad.Rate.format(rate, locale: :en)
      {:ok, "$99.00/week"}

  """
  @spec format(t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def format(%__MODULE__{} = rate, options \\ []) do
    locale = Keyword.get_lazy(options, :locale, &Localize.get_locale/0)

    with {:ok, amount} <- Money.to_string(rate.amount, locale: locale),
         {:ok, per} <- singular_name(rate.per, locale) do
      {:ok, "#{amount}/#{per}"}
    end
  end

  # `display_name/2` gives the plural — "weeks" — and a rate reads as
  # "$99.00/week". Formatting a quantity of one and dropping the number gets
  # the singular from CLDR's own plural rules, which is the only way to be
  # right in a language with more than two plural categories.
  defp singular_name(%Unit{} = unit, locale) do
    with {:ok, formatted} <- Unit.to_string(%{unit | value: 1}, locale: locale),
         {:ok, one} <- Localize.Number.to_string(1, locale: locale) do
      {:ok, formatted |> String.replace_prefix(one, "") |> String.trim()}
    end
  end
end
