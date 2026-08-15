defmodule LocalizePad.Evaluator do
  @moduledoc """
  Evaluates a `LocalizePad.Parser` AST to a value.

  ## The value lattice, so far

  M1 covers two kinds: plain numbers and `Localize.Unit` quantities.
  Percentages, money, rates and temporal values join them in later milestones,
  and each will widen the arithmetic tables below rather than replace them.

  ## Units are values, not annotations

  Because the parser treats a unit as an operand meaning "one of these",
  `3 meters` arrives as `3 × meter` and the multiplication does the work of
  building the quantity. Compound units fall out of the same rule: `m/s` is a
  division of two quantities, and `Localize.Unit.Math` produces
  `meter-per-second` without this module knowing anything about compound
  naming.

  ## Nothing raises

  This runs on the render path of a live document. Every clause returns
  `{:ok, value}` or `{:error, reason}`; a line that cannot be evaluated shows
  no answer, and never takes the sheet down with it. That includes arithmetic
  that is meaningless rather than merely wrong — adding seconds to metres, or
  dividing by zero.

  """

  alias Localize.Unit
  alias Localize.Unit.Math
  alias LocalizePad.{Parser, Percentage, Rate, SalesTax, Temporal}
  alias LocalizePad.Temporal.Zones

  # `Decimal` is in the lattice even though nothing in M1 produces one: the
  # number scanner can be asked for decimals, `Localize.Unit` values may carry
  # them, and money will bring them in as a matter of course. Declaring it now
  # keeps the defensive clauses below reachable — the alternative, a narrower
  # type, makes dialyzer prune them as dead and a stray Decimal then raises on
  # the render path.
  @type value ::
          number()
          | Decimal.t()
          | Unit.t()
          | Tempo.t()
          | Tempo.Duration.t()
          | Localize.Duration.t()
          | DateTime.t()
          | Zones.t()
          | Percentage.t()
          | Money.t()
          # Conversion targets rather than quantities: the `EUR` in
          # `10 USD in EUR`, and the `€/month` in `€30/day in €/month`.
          | {:currency, atom()}
          | {:rate_target, atom(), Unit.t()}
          | Rate.t()
          | SalesTax.t()
  @type environment :: %{optional(String.t()) => value()}

  @doc """
  Evaluates an AST.

  ### Arguments

  * `ast` - the tree produced by `LocalizePad.Parser.parse/2`.

  * `environment` - a map of variable name to value. Defaults to `%{}`.

  ### Returns

  * `{:ok, value}` where value is a number or a `t:Localize.Unit.t/0`.

  * `{:error, reason}` when the expression cannot be evaluated — an unbound
    variable, incompatible units, an unknown unit name, or division by zero.

  ### Examples

      iex> {:ok, tokens} = LocalizePad.Tokenizer.tokenize("2 + 3", locale: :en)
      iex> {:ok, ast} = LocalizePad.Parser.parse(tokens)
      iex> LocalizePad.Evaluator.eval(ast)
      {:ok, 5}

      iex> {:ok, tokens} = LocalizePad.Tokenizer.tokenize("3 meters to feet", locale: :en)
      iex> {:ok, ast} = LocalizePad.Parser.parse(tokens)
      iex> {:ok, result} = LocalizePad.Evaluator.eval(ast)
      iex> result.name
      "foot"

  """
  @spec eval(Parser.ast(), environment()) :: {:ok, value()} | {:error, term()}
  def eval(ast, environment \\ %{})

  def eval({:number, value}, _environment) do
    {:ok, value}
  end

  def eval({:unit, name}, _environment) do
    Unit.new(1, name)
  end

  def eval({:temporal, fields}, _environment) do
    Temporal.resolve(fields)
  end

  def eval({:zone, zone}, _environment) do
    {:ok, zone}
  end

  def eval({:percentage, value}, _environment) do
    {:ok, Percentage.new(value)}
  end

  def eval({:money, money}, _environment) do
    {:ok, money}
  end

  def eval({:currency, code}, _environment) do
    {:ok, {:currency, code}}
  end

  def eval({:tax, tax}, _environment) do
    {:ok, tax}
  end

  def eval({:phrase, preposition, left, right}, environment) do
    with {:ok, left_value} <- eval(left, environment),
         {:ok, right_value} <- eval(right, environment) do
      apply_phrase(preposition, left_value, right_value)
    end
  end

  def eval({:variable, name}, environment) do
    case Map.fetch(environment, name) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:unbound_variable, name}}
    end
  end

  def eval({:neg, expression}, environment) do
    with {:ok, value} <- eval(expression, environment) do
      negate(value)
    end
  end

  def eval({:binary, operator, left, right}, environment) do
    with {:ok, left_value} <- eval(left, environment),
         {:ok, right_value} <- eval(right, environment) do
      apply_operator(operator, left_value, right_value)
    end
  end

  def eval({:convert, expression, target}, environment) do
    with {:ok, value} <- eval(expression, environment),
         {:ok, target_unit} <- eval(target, environment) do
      convert(value, target_unit)
    end
  end

  def eval(other, _environment) do
    {:error, {:cannot_evaluate, other}}
  end

  # ── Negation ────────────────────────────────────────────────────────────

  defp negate(value) when is_number(value), do: {:ok, -value}
  defp negate(%Unit{} = unit), do: {:ok, Math.negate(unit)}

  # ── Arithmetic ──────────────────────────────────────────────────────────

  defp apply_operator(:add, left, right) when is_number(left) and is_number(right) do
    {:ok, left + right}
  end

  defp apply_operator(:sub, left, right) when is_number(left) and is_number(right) do
    {:ok, left - right}
  end

  defp apply_operator(:mul, left, right) when is_number(left) and is_number(right) do
    {:ok, left * right}
  end

  defp apply_operator(:div, _left, right) when right == 0 do
    {:error, :division_by_zero}
  end

  defp apply_operator(:div, left, right) when is_number(left) and is_number(right) do
    {:ok, left / right}
  end

  defp apply_operator(:pow, left, right) when is_number(left) and is_number(right) do
    {:ok, power(left, right)}
  end

  # Addition and subtraction need conformable quantities. `Localize.Unit.Math`
  # converts the right operand into the left's unit and reports a
  # `UnitConversionError` when the dimensions disagree, which is exactly the
  # message the user needs.
  defp apply_operator(:add, %Unit{} = left, %Unit{} = right), do: Math.add(left, right)
  defp apply_operator(:sub, %Unit{} = left, %Unit{} = right), do: Math.sub(left, right)

  # A quantity plus a bare number is meaningless — `3 metres + 2` has no
  # answer, and guessing one would be worse than declining.
  defp apply_operator(operator, %Unit{} = left, right)
       when operator in [:add, :sub] and is_number(right) do
    {:error, {:incompatible, left.name, :number}}
  end

  defp apply_operator(operator, left, %Unit{} = right)
       when operator in [:add, :sub] and is_number(left) do
    {:error, {:incompatible, :number, right.name}}
  end

  defp apply_operator(:mul, %Unit{} = left, %Unit{} = right), do: Math.mult(left, right)

  # Multiplication is commutative, but `Math.mult/2` wants the quantity first —
  # and `3 meters` reaches us as `3 × meter`, number first.
  defp apply_operator(:mul, %Unit{} = left, right) when is_number(right) do
    Math.mult(left, right)
  end

  defp apply_operator(:mul, left, %Unit{} = right) when is_number(left) do
    Math.mult(right, left)
  end

  defp apply_operator(:div, %Unit{} = left, %Unit{} = right), do: Math.div(left, right)

  defp apply_operator(:div, %Unit{} = left, right) when is_number(right) do
    Math.div(left, right)
  end

  # A number over a quantity is that number times the quantity's reciprocal:
  # `60 / (1 hour)` is 60 per hour.
  defp apply_operator(:div, left, %Unit{} = right) when is_number(left) do
    with {:ok, inverted} <- Math.invert(right) do
      Math.mult(inverted, left)
    end
  end

  # `m^2` is `m × m`. Only whole, positive powers are supported here; the
  # general case needs dimension arithmetic that arrives with the unit work in
  # a later milestone.
  defp apply_operator(:pow, %Unit{} = left, right) when is_integer(right) and right > 0 do
    Enum.reduce_while(2..right//1, {:ok, left}, fn _step, {:ok, accumulated} ->
      case Math.mult(accumulated, left) do
        {:ok, product} -> {:cont, {:ok, product}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  # ── Money ───────────────────────────────────────────────────────────────

  defp apply_operator(:add, %Money{} = left, %Money{} = right), do: Money.add(left, right)
  defp apply_operator(:sub, %Money{} = left, %Money{} = right), do: Money.sub(left, right)

  defp apply_operator(:mul, %Money{} = left, right) when is_number(right) do
    Money.mult(left, right)
  end

  defp apply_operator(:mul, left, %Money{} = right) when is_number(left) do
    Money.mult(right, left)
  end

  defp apply_operator(:div, %Money{} = left, right) when is_number(right) and right != 0 do
    Money.div(left, right)
  end

  # Money over money is a ratio, and a ratio is a plain number — `$50 / $200`
  # is a quarter, not a quarter of a dollar.
  defp apply_operator(:div, %Money{} = left, %Money{} = right) do
    if Decimal.equal?(right.amount, 0) do
      {:error, :division_by_zero}
    else
      {:ok, Decimal.to_float(Decimal.div(left.amount, right.amount))}
    end
  end

  # A percentage of money keeps the currency, and the rounding rules that go
  # with it: `$300 + 15%` is $345.00.
  defp apply_operator(operator, %Money{} = left, %Percentage{} = right)
       when operator in [:add, :sub] do
    with {:ok, portion} <- Money.mult(left, Percentage.to_decimal(right)) do
      apply_operator(operator, left, portion)
    end
  end

  defp apply_operator(:mul, %Money{} = left, %Percentage{} = right) do
    Money.mult(left, Percentage.to_decimal(right))
  end

  defp apply_operator(:mul, %Percentage{} = left, %Money{} = right) do
    Money.mult(right, Percentage.to_decimal(left))
  end

  # `$300 + VAT` grosses a net price up.
  defp apply_operator(:add, %Money{} = money, %SalesTax{} = tax) do
    Money.mult(money, SalesTax.gross_multiplier(tax))
  end

  # `$300 - VAT` recovers the net price from a gross one, which is division by
  # 1.15 rather than subtraction of 15%. Subtracting would be wrong by the
  # tax on the tax.
  defp apply_operator(:sub, %Money{} = money, %SalesTax{} = tax) do
    Money.div(money, SalesTax.gross_multiplier(tax))
  end

  # ── Rates ───────────────────────────────────────────────────────────────

  # `$99 per week`. Only money needs a rate type; a quantity over a unit is
  # already a compound unit and the unit engine handles it.
  defp apply_operator(:div, %Money{} = left, %Unit{} = right) do
    Rate.new(left, right)
  end

  # `$50/week × 12 weeks` is the whole point of having rates.
  defp apply_operator(:mul, %Rate{} = left, %Unit{} = right), do: Rate.multiply(left, right)
  defp apply_operator(:mul, %Unit{} = left, %Rate{} = right), do: Rate.multiply(right, left)

  defp apply_operator(:add, %Rate{} = left, %Rate{} = right), do: Rate.add(left, right)

  defp apply_operator(:mul, %Rate{} = left, right) when is_number(right) do
    with {:ok, amount} <- Money.mult(left.amount, right) do
      {:ok, %{left | amount: amount}}
    end
  end

  # A currency over a unit is not a value but the *shape* of one: the `€/month`
  # in `€30/day in €/month`. It only ever appears as a conversion target.
  defp apply_operator(:div, {:currency, code}, %Unit{} = right) do
    {:ok, {:rate_target, code, right}}
  end

  # ── Percentages ─────────────────────────────────────────────────────────
  #
  # The rules read oddly in isolation but are exactly what people mean. See
  # the table in `LocalizePad.Percentage`.

  # Two percentages have nothing to be a percentage *of*, so they combine as
  # percentages: `10% + 20%` is 30%.
  defp apply_operator(operator, %Percentage{} = left, %Percentage{} = right)
       when operator in [:add, :sub] do
    combined = plain(operator, left.value, right.value)
    {:ok, Percentage.new(combined)}
  end

  # A bare number in the company of a percentage is read as a proportion, so
  # `30% + 0.4` is 70% rather than 30.4%.
  defp apply_operator(operator, %Percentage{} = left, right)
       when operator in [:add, :sub] and is_number(right) do
    apply_operator(operator, left, Percentage.coerce(right))
  end

  # But a percentage applied *to* something is relative to that something:
  # `200 + 10%` is 220, not 200.1.
  defp apply_operator(operator, left, %Percentage{} = right)
       when operator in [:add, :sub] and is_number(left) do
    {:ok, plain(operator, left, Percentage.of(right, left))}
  end

  # Multiplication and division always yield a plain number, whichever side
  # the percentage is on: `50% × 30` and `30 × 50%` are both 15.
  defp apply_operator(:mul, %Percentage{} = left, right) when is_number(right) do
    {:ok, Percentage.of(left, right)}
  end

  defp apply_operator(:mul, left, %Percentage{} = right) when is_number(left) do
    {:ok, Percentage.of(right, left)}
  end

  defp apply_operator(:mul, %Percentage{} = left, %Percentage{} = right) do
    {:ok, Percentage.new(Percentage.of(left, right.value))}
  end

  defp apply_operator(:div, %Percentage{} = left, right)
       when is_number(right) and right != 0 do
    {:ok, Percentage.new(left.value / right)}
  end

  # A percentage of a quantity keeps the quantity: `100 metres + 15%` is 115
  # metres, and the unit engine does the arithmetic.
  defp apply_operator(operator, %Unit{} = left, %Percentage{} = right)
       when operator in [:add, :sub] do
    with {:ok, portion} <- Math.mult(left, Percentage.to_decimal(right)) do
      apply_operator(operator, left, portion)
    end
  end

  defp apply_operator(:mul, %Unit{} = left, %Percentage{} = right) do
    Math.mult(left, Percentage.to_decimal(right))
  end

  defp apply_operator(:mul, %Percentage{} = left, %Unit{} = right) do
    Math.mult(right, Percentage.to_decimal(left))
  end

  # ── Zones ───────────────────────────────────────────────────────────────

  # `6pm Sydney` reaches here as juxtaposition — the same implicit
  # multiplication that builds `3 meters` — because a zone sits beside a time
  # exactly as a unit sits beside a number.
  defp apply_operator(:mul, %Tempo{} = left, %Zones{} = zone) do
    Temporal.in_zone(left, zone)
  end

  defp apply_operator(:mul, %Zones{} = zone, %Tempo{} = right) do
    Temporal.in_zone(right, zone)
  end

  # A zone with nothing to anchor it is not a value. `flight to Paris` must
  # stay an ordinary note rather than becoming a clock reading, so this
  # declines rather than inventing "the time in Paris".
  defp apply_operator(_operator, %Zones{}, _right), do: {:error, :bare_zone}
  defp apply_operator(_operator, _left, %Zones{}), do: {:error, :bare_zone}

  # ── Temporal arithmetic ─────────────────────────────────────────────────

  # `June 12 + 3 weeks`. The duration arrives as an ordinary unit quantity,
  # because the unit engine already knows what a week is; `Temporal.duration/1`
  # is the only adapter needed.
  defp apply_operator(operator, %Tempo{} = left, %Unit{} = right)
       when operator in [:add, :sub] do
    with {:ok, duration} <- Temporal.duration(right) do
      shift(left, duration, operator)
    end
  end

  # `3 weeks after June 12` reads the other way round, and addition commutes.
  defp apply_operator(:add, %Unit{} = left, %Tempo{} = right) do
    with {:ok, duration} <- Temporal.duration(left) do
      shift(right, duration, :add)
    end
  end

  # `January 10 - February 5` is the span *between* two dates, not a
  # subtraction of one instant from another — so the operands run left to
  # right, earlier to later, and the answer is a duration rather than a date.
  #
  # The answer comes back as a `Localize.Duration` rather than Tempo's own,
  # because the two count differently and only one of them is readable: Tempo
  # measures the span exactly, in seconds, while `Localize.Duration` breaks it
  # into calendar components and renders them in the sheet's locale — "26
  # days", "26 Tage". Seconds are the right internal answer and the wrong thing
  # to show someone.
  defp apply_operator(:sub, %Tempo{} = left, %Tempo{} = right) do
    with {:ok, from} <- Tempo.to_date(left),
         {:ok, to} <- Tempo.to_date(right) do
      Localize.Duration.new(from, to)
    else
      # Time-only values have no date to span across, so they get the
      # clock-time reading instead.
      _not_a_date -> clock_span(left, right)
    end
  end

  defp apply_operator(operator, left, right) do
    {:error, {:unsupported_operation, operator, describe(left), describe(right)}}
  end

  # ── Prepositional phrases ───────────────────────────────────────────────
  #
  # `of`, `off` and `on` put the operator first and the amount second, the
  # reverse of `200 + 10%`. The preposition survives into the tree because it
  # distinguishes readings the operands cannot: `VAT on $300` treats $300 as a
  # net price, `VAT of $300` as a gross one.

  # Percentages: `10% of 200` is the portion, `off` and `on` the whole less or
  # plus that portion.
  defp apply_phrase(:of, %Percentage{} = percentage, value) do
    apply_operator(:mul, value, percentage)
  end

  defp apply_phrase(:off, %Percentage{} = percentage, value) do
    apply_operator(:sub, value, percentage)
  end

  defp apply_phrase(:on, %Percentage{} = percentage, value) do
    apply_operator(:add, value, percentage)
  end

  # Sales tax. See `LocalizePad.SalesTax` for why `on` and `of` differ.
  defp apply_phrase(:on, %SalesTax{} = tax, %Money{} = money) do
    apply_operator(:mul, money, tax.rate)
  end

  defp apply_phrase(:off, %SalesTax{} = tax, %Money{} = money) do
    Money.div(money, SalesTax.gross_multiplier(tax))
  end

  defp apply_phrase(:of, %SalesTax{} = tax, %Money{} = money) do
    with {:ok, net} <- Money.div(money, SalesTax.gross_multiplier(tax)) do
      Money.sub(money, net)
    end
  end

  defp apply_phrase(preposition, left, right) do
    {:error, {:unsupported_phrase, preposition, describe(left), describe(right)}}
  end

  # Two clock times bound a span rather than subtracting. Soulver's own
  # documentation concedes the minus sign is ambiguous here — `5pm - 7pm` is
  # read by most people as a range and `5pm - 2pm` as a subtraction — and
  # resolves it by always measuring the gap. So do we: the answer is a
  # duration either way, which is what makes both readings agree.
  #
  # When the second time is earlier on the clock it means the following day,
  # so `4pm to 3am` is eleven hours rather than negative thirteen.
  defp clock_span(left, right) do
    with {:ok, from} <- Temporal.to_time(left),
         {:ok, to} <- Temporal.to_time(right) do
      seconds = Time.diff(to, from)
      seconds = if seconds < 0, do: seconds + 86_400, else: seconds

      normalize(Localize.Duration.new_from_seconds(seconds))
    else
      _not_a_time -> normalize(Tempo.duration(left, right))
    end
  end

  defp shift(%Tempo{} = tempo, duration, :add) do
    normalize(Tempo.shift(tempo, duration))
  end

  defp shift(%Tempo{} = tempo, duration, :sub) do
    normalize(Tempo.shift(tempo, Tempo.Duration.negate(duration)))
  end

  # Tempo returns some results bare and others wrapped. This evaluator's
  # contract is uniformly `{:ok, value} | {:error, reason}`, so normalise at
  # the boundary rather than letting the shape leak into every caller.
  defp normalize({:ok, value}), do: {:ok, value}
  defp normalize({:error, reason}), do: {:error, reason}
  defp normalize(value), do: {:ok, value}

  defp plain(:add, left, right), do: left + right
  defp plain(:sub, left, right), do: left - right

  defp power(base, exponent) when is_integer(base) and is_integer(exponent) and exponent >= 0 do
    Integer.pow(base, exponent)
  end

  defp power(base, exponent) do
    :math.pow(base, exponent)
  end

  # ── Conversion ──────────────────────────────────────────────────────────

  defp convert(%Unit{} = source, %Unit{} = target) do
    Unit.convert(source, target.name)
  end

  # `7:30 to 20:45` and `3 March to 30 May` read `to` as a range rather than a
  # conversion — the answer is how much time lies between the two, which is the
  # same thing the minus sign produces for a pair of temporal values.
  defp convert(%Tempo{} = from, %Tempo{} = to) do
    apply_operator(:sub, from, to)
  end

  # `6pm Sydney in Chicago` — the source is already anchored to a zone, so this
  # is the shift to the target one.
  defp convert(%DateTime{} = datetime, %Zones{name: name}) do
    case DateTime.shift_zone(datetime, name) do
      {:ok, shifted} -> {:ok, shifted}
      {:error, reason} -> {:error, {:unknown_zone, name, reason}}
    end
  end

  # `10 USD in EUR`. Exchange rates are fetched by `Money.ExchangeRates`, which
  # needs an Open Exchange Rates app id; without one the retriever has no rates
  # and this reports that rather than inventing a number.
  defp convert(%Money{} = money, {:currency, code}) do
    # Money reports every failure as `{:error, {exception_module, message}}`,
    # so there is no second error shape to handle.
    case Money.to_currency(money, code) do
      {:ok, converted} -> {:ok, converted}
      {:error, {_module, _message}} -> {:error, {:no_exchange_rate, money.currency, code}}
    end
  end

  # `$30/day in month` and `€30/day in €/month` both ask for the same thing.
  defp convert(%Rate{} = rate, %Unit{} = target), do: Rate.convert(rate, target)

  defp convert(%Rate{} = rate, {:rate_target, _code, target}) do
    Rate.convert(rate, target)
  end

  # A bare time with no source zone cannot be converted — `6pm in Chicago`
  # leaves out where 6pm *is*, and guessing the sheet's own zone would be a
  # different answer for every reader.
  defp convert(%Tempo{}, %Zones{}) do
    {:error, :zone_without_source}
  end

  # Converting a bare number has no meaning yet. `20% as decimal` and
  # `$100 as number` are phrase forms that arrive with the percentage and money
  # work; until then this declines rather than inventing a reading.
  defp convert(source, target) do
    {:error, {:cannot_convert, describe(source), describe(target)}}
  end

  defp describe(%Unit{} = unit), do: unit.name
  defp describe(%Tempo{}), do: :temporal
  defp describe(%Tempo.Duration{}), do: :duration
  defp describe(%Localize.Duration{}), do: :duration
  defp describe(%Zones{name: name}), do: name
  defp describe(%DateTime{}), do: :zoned_time
  defp describe(%Percentage{}), do: :percentage
  defp describe(%Money{currency: code}), do: code
  defp describe(%Rate{}), do: :rate
  defp describe(%SalesTax{name: name}), do: name
  defp describe(value) when is_number(value), do: :number
  defp describe(other), do: other
end
