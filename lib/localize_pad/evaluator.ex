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
  alias LocalizePad.{Parser, Temporal}

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
      # Time-only values have no date to span, so fall back to Tempo's exact
      # measurement rather than declining outright.
      _not_a_date -> normalize(Tempo.duration(left, right))
    end
  end

  defp apply_operator(operator, left, right) do
    {:error, {:unsupported_operation, operator, describe(left), describe(right)}}
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
  defp describe(value) when is_number(value), do: :number
  defp describe(other), do: other
end
