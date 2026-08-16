defmodule LocalizePad.Finance do
  @moduledoc """
  The financial phrases: compound interest, present value, loan repayments.

  ## Matching by slot type, not by word order

  These phrases have three or four slots and a great many ways of joining them:

      $1,000 after 3 years at 7%
      interest on $1,000 for 3 years @ 7% compounding monthly
      monthly repayment on $10,000 over 6 years at 6%
      present value of $1,000 after 20 years at 10%

  Writing a grammar for `on`/`of`/`for`/`after`/`over`/`at`/`@` and every
  ordering would be a large table of near-duplicates. But the slots are
  unambiguous *by type*: there is exactly one money amount, one duration and
  one percentage, and no reading in which they could be confused. So this
  matcher identifies the phrase from its noun and then takes each slot by
  type, ignoring the connecting words entirely.

  That is the same forgiveness the rest of the language relies on, applied one
  level up — and it means `monthly repayment on $10,000 over 6 years at 6%` and
  `monthly repayment: $10,000, 6 years, 6%` both work without either being
  written down as a pattern.

  ## Which convention the answers use

  All of it — compound interest, interest earned, present value and loan
  repayment — agrees with Soulver to the cent, using the standard amortization
  formula through `Money.Financial.payment/3`: a periodic rate over a periodic
  count. `$10,000 over 6 years at 6%` repaid monthly is $165.73 either way.

  `total repayment` is the monthly payment across every month of the term,
  monthly being the cadence loans are actually repaid on, and `total interest`
  is that total less the principal. `monthly interest` is the *average* monthly
  interest over the life of the loan, which is what Soulver's own
  documentation says it means — real amortized interest falls as the principal
  is paid down.

  """

  alias LocalizePad.{Percentage, Token}

  @periods_per_year %{
    daily: 365,
    weekly: 52,
    monthly: 12,
    quarterly: 4,
    annually: 1
  }

  @frequencies %{
    "daily" => :daily,
    "weekly" => :weekly,
    "monthly" => :monthly,
    "quarterly" => :quarterly,
    "annual" => :annually,
    "annually" => :annually,
    "yearly" => :annually
  }

  @calendar_units ~w(year month week day)

  # The nouns and qualifiers that name a calculation, as against the numbers
  # and units it works on.
  @phrase_words ~w(
    repayment repayments interest present value
    after at over for total compounding compounded
  )

  @doc """
  The words this module had to be told.

  TEMPORARY, for a demo — see `LocalizePad.Lexicon.authored/1`.

  ### Returns

  * A list of lowercased forms.

  ### Examples

      iex> "monthly" in LocalizePad.Finance.authored()
      true

  """
  @spec authored() :: [String.t()]
  def authored, do: Map.keys(@frequencies) ++ @phrase_words

  @type slots :: %{
          principal: Money.t(),
          rate: Percentage.t(),
          years: number(),
          compounding: atom(),
          frequency: atom() | nil
        }

  @doc """
  Recognises a financial phrase in a token stream.

  ### Arguments

  * `tokens` - the tokens for one line.

  ### Returns

  * `{:ok, {:finance, kind, slots}}` when the line names a financial
    calculation and supplies all three slots.

  * `:error` otherwise, which is the common case — the line is then parsed as
    an ordinary expression.

  ### Examples

      iex> {:ok, tokens} =
      ...>   LocalizePad.Tokenizer.tokenize("$1,000 after 3 years at 7%", locale: :en)
      iex> {:ok, {:finance, kind, _slots}} = LocalizePad.Finance.match(tokens)
      iex> kind
      :future_value

  """
  @spec match([Token.t()]) :: {:ok, {:finance, atom(), slots()}} | :error
  def match(tokens) when is_list(tokens) do
    words = Enum.map(tokens, &String.downcase(&1.source))

    with {:ok, kind} <- kind(words),
         {:ok, principal} <- take_money(tokens),
         {:ok, rate} <- take_percentage(tokens),
         {:ok, years} <- take_years(tokens) do
      slots = %{
        principal: principal,
        rate: rate,
        years: years,
        compounding: compounding(words),
        frequency: frequency(words)
      }

      {:ok, {:finance, kind, slots}}
    end
  end

  # The noun decides the calculation; a frequency qualifier in front of
  # `interest` decides whether it is interest *earned* on savings or interest
  # *paid* on a loan.
  defp kind(words) do
    cond do
      names?(words, ["repayment", "repayments"]) -> {:ok, :repayment}
      names?(words, ["interest"]) -> interest_kind(words)
      names?(words, ["present"]) and names?(words, ["value"]) -> {:ok, :present_value}
      names?(words, ["after", "at", "@", "over", "for"]) -> {:ok, :future_value}
      true -> :error
    end
  end

  # Interest *earned* on savings, or interest *paid* on a loan. A frequency
  # qualifier — "monthly interest", "total interest" — marks the loan reading.
  defp interest_kind(words) do
    if frequency(words), do: {:ok, :loan_interest}, else: {:ok, :interest}
  end

  defp names?(words, candidates), do: Enum.any?(candidates, &(&1 in words))

  defp frequency(words) do
    Enum.find_value(words, fn word ->
      if word == "total", do: :total, else: Map.get(@frequencies, word)
    end)
  end

  # `compounding monthly` overrides the default of yearly compounding.
  defp compounding(words) do
    case Enum.find_index(words, &(&1 in ["compounding", "compounded"])) do
      nil -> :annually
      index -> words |> Enum.at(index + 1) |> then(&Map.get(@frequencies, &1, :annually))
    end
  end

  defp take_money(tokens) do
    case Enum.find(tokens, &(&1.kind == :money)) do
      %Token{value: money} -> {:ok, money}
      nil -> :error
    end
  end

  defp take_percentage(tokens) do
    case Enum.find(tokens, &(&1.kind == :percentage)) do
      %Token{value: value} -> {:ok, Percentage.new(value)}
      nil -> :error
    end
  end

  # A duration is a number beside a calendar unit. Everything is normalised to
  # years because that is the unit interest rates are quoted in.
  defp take_years(tokens) do
    tokens
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.find_value(:error, fn
      [%Token{kind: :number, value: count}, %Token{kind: :unit, value: unit}] ->
        if unit in @calendar_units, do: {:ok, count * years_per(unit)}

      _other ->
        nil
    end)
  end

  defp years_per("year"), do: 1
  defp years_per("month"), do: 1 / 12
  defp years_per("week"), do: 1 / 52
  defp years_per("day"), do: 1 / 365

  @doc """
  Evaluates a matched financial phrase.

  ### Arguments

  * `kind` - the calculation, from `match/1`.

  * `slots` - the principal, rate, term and compounding frequency.

  ### Returns

  * `{:ok, money}` for the amount calculations.

  * `{:error, reason}` when the figures make no sense — a term of zero years,
    or a rate of zero where the formula divides by it.

  """
  @spec evaluate(atom(), slots()) :: {:ok, Money.t()} | {:error, term()}
  def evaluate(kind, slots)

  def evaluate(:future_value, slots) do
    with {:ok, periods, rate} <- periodic(slots, slots.compounding) do
      {:ok, Money.Financial.future_value(slots.principal, rate, periods)}
    end
  end

  def evaluate(:interest, slots) do
    with {:ok, grown} <- evaluate(:future_value, slots) do
      Money.sub(grown, slots.principal)
    end
  end

  def evaluate(:present_value, slots) do
    with {:ok, periods, rate} <- periodic(slots, slots.compounding) do
      {:ok, Money.Financial.present_value(slots.principal, rate, periods)}
    end
  end

  def evaluate(:repayment, %{frequency: :total} = slots) do
    total_repayment(slots)
  end

  def evaluate(:repayment, slots) do
    with {:ok, periods, rate} <- periodic(slots, slots.frequency || :monthly) do
      {:ok, Money.Financial.payment(slots.principal, rate, periods)}
    end
  end

  def evaluate(:loan_interest, %{frequency: :total} = slots) do
    with {:ok, total} <- total_repayment(slots) do
      Money.sub(total, slots.principal)
    end
  end

  # The average over the life of the loan, not the interest in any particular
  # period — amortized interest falls as the principal is paid down.
  def evaluate(:loan_interest, slots) do
    with {:ok, total} <- total_repayment(slots),
         {:ok, interest} <- Money.sub(total, slots.principal),
         {:ok, periods, _rate} <- periodic(slots, slots.frequency || :monthly) do
      Money.div(interest, periods)
    end
  end

  defp total_repayment(slots) do
    with {:ok, periods, rate} <- periodic(slots, :monthly) do
      slots.principal
      |> Money.Financial.payment(rate, periods)
      |> Money.mult(periods)
    end
  end

  # `Money.Financial` wants a rate per period and a count of periods, so an
  # annual rate over a term in years is divided and multiplied accordingly.
  defp periodic(slots, frequency) do
    per_year = Map.get(@periods_per_year, frequency, 1)
    periods = slots.years * per_year
    rate = Percentage.to_decimal(slots.rate) / per_year

    cond do
      periods <= 0 -> {:error, :term_must_be_positive}
      rate <= 0 -> {:error, :rate_must_be_positive}
      true -> {:ok, periods, rate}
    end
  end
end
