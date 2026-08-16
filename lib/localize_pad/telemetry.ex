defmodule LocalizePad.Telemetry do
  @moduledoc """
  What the engine reports about itself, and what it deliberately does not.

  ## Refusals are the interesting event

  A line that evaluates is unremarkable. A line that does not is somebody who
  expected a phrase to work, and there is no other way to learn which phrases
  those are — the language was designed against a hypothesis about how people
  write sums, and only refusals say where the hypothesis is wrong.

  ## No source text, ever

  This is the constraint the rest of the module is shaped by. A sheet lives in
  the browser and in the links people share; the server never stores one, and
  telemetry must not become the exception that quietly makes that untrue.

  So an event carries three things, none of which are what anyone typed:

  * the *category* of the failure — `:no_expression`, `:unexpected` — and not
    its payload. `{:unexpected, "in"}` names the word that stopped the parse,
    which is the single most useful thing here and is also, literally, user
    text. It is dropped.

  * the *shape* of the line, as the sequence of token kinds. `number keyword
    number word` says a phrase form failed without saying what the phrase was.

  * the language, narrowed to its subtag.

  The cost is real: shapes are a blunter instrument than phrases, and some
  refusals will be legible only as "a lot of `word word number` lines fail in
  German". That is the price of the promise, and the promise is load-bearing —
  it is why sharing needs no account and why a sheet can hold something private
  without anyone having to think about it.

  ## Attaching to it

  Nothing here handles the event. `LocalizePadWeb.Telemetry` turns it into a
  metric; a deployment wanting more can attach its own handler to
  `[:localize_pad, :line, :refused]`.

  """

  @refused [:localize_pad, :line, :refused]

  @doc """
  Reports that a line did not evaluate.

  ### Arguments

  * `reason` - the error the line carried, of any shape. Only its category
    survives into the event.

  * `tokens` - the line's tokens, reduced to their kinds.

  * `locale` - the locale the line was read in.

  ### Returns

  * `:ok`.

  ### Examples

      iex> LocalizePad.Telemetry.refused(:no_expression, [], :en)
      :ok

  """
  @spec refused(term(), [LocalizePad.Token.t()], term()) :: :ok
  def refused(reason, tokens, locale) do
    :telemetry.execute(
      @refused,
      %{count: 1},
      %{reason: category(reason), shape: shape(tokens), locale: language(locale)}
    )
  end

  @doc """
  The event name refusals are reported under.

  ### Returns

  * The `:telemetry` event name, as a list of atoms.

  ### Examples

      iex> LocalizePad.Telemetry.refused_event()
      [:localize_pad, :line, :refused]

  """
  @spec refused_event() :: [atom()]
  def refused_event, do: @refused

  # Only the leading atom. Every payload these tuples carry is either the
  # user's own word or a unit name it resolved to, and neither belongs here.
  defp category(reason) when is_atom(reason), do: reason
  defp category(reason) when is_tuple(reason) and tuple_size(reason) > 0, do: elem(reason, 0)
  defp category(%module{}), do: module
  defp category(_reason), do: :unknown

  # The kinds in order, which describes the grammar of the line and nothing
  # about its content. Bounded length, because a metric label should not grow
  # with whatever someone pasted in.
  defp shape(tokens) do
    tokens
    |> Enum.take(12)
    |> Enum.map_join(" ", &to_string(&1.kind))
  end

  defp language(locale) do
    case Localize.validate_locale(locale) do
      {:ok, language_tag} -> to_string(language_tag.language)
      {:error, _reason} -> "unknown"
    end
  end
end
