defmodule LocalizePad.Refusal do
  @moduledoc """
  Turns a refusal reason into something a reader can act on.

  A line that cannot be answered goes blank, which is correct — a wrong answer
  is far worse than no answer — but blankness alone does not say *why*, and a
  reader who cannot tell the difference between "this line is prose" and "this
  line needs one more fact from you" will assume the app is broken.

  Only reasons the reader can actually fix get a message. Everything else
  returns `nil` and stays quiet, because a message that says "no expression"
  next to a line of prose is noise on every sheet.

  """

  use Localize.Message.Sigils,
    backend: LocalizePad.Gettext,
    sigils: [domain: "answers"]

  @doc """
  A short, localized explanation of a refusal.

  ### Arguments

  * `reason` - the reason from `t:LocalizePad.Line.t/0`'s `:error`.

  ### Options

  * `:locale` - the locale to render in. Defaults to the current locale.

  ### Returns

  * A string, or `nil` when the reason is not one the reader can act on.

  ### Examples

      iex> LocalizePad.Refusal.message({:undeclared_rate, "VAT"}, locale: :en)
      "no rate declared — add VAT = 20%"

      iex> LocalizePad.Refusal.message(:no_expression, locale: :en)
      nil

  """
  @spec message(term(), keyword()) :: String.t() | nil
  def message(reason, options \\ [])

  def message({:undeclared_rate, name}, options) when is_binary(name) do
    with_locale(options, fn -> ~t"no rate declared — add #{example = name <> " = 20%"}" end)
  end

  # The reader's own zone comes from the browser, so this is what a line asking
  # for sunrise says before the page has connected, or where the browser will
  # not say where it is. Naming a place is the fix either way.
  def message({:no_location, event}, options) when is_atom(event) do
    with_locale(options, fn -> ~t"which place? — try #{example = "#{event} in Sydney"}" end)
  end

  def message({:unknown_place, place}, options) when is_binary(place) do
    with_locale(options, fn -> ~t"where is #{name = place}?" end)
  end

  # High latitudes, in season. Not a mistake to correct — the sun really does
  # not rise — so the message says which event did not happen rather than
  # suggesting a repair.
  #
  # One whole sentence per event rather than a frame with the event's name
  # dropped into it. A noun in a slot is a sentence assembled by this file
  # instead of by the translator, and the assembly is only ever correct in the
  # language it was written in: German wants `kein Sonnenaufgang`, French
  # `pas de lever de soleil`, and neither is `no` plus a word.
  def message({:no_event, :sunrise}, options) do
    with_locale(options, fn -> ~t"no sunrise there that day" end)
  end

  def message({:no_event, :sunset}, options) do
    with_locale(options, fn -> ~t"no sunset there that day" end)
  end

  def message({:no_event, :moonrise}, options) do
    with_locale(options, fn -> ~t"the moon does not rise there that day" end)
  end

  def message({:no_event, :moonset}, options) do
    with_locale(options, fn -> ~t"the moon does not set there that day" end)
  end

  # A stop with no trip above it. The itinerary is the thing that gives a stop
  # its dates, so naming one is the whole fix.
  def message(:no_trip, options) do
    with_locale(options, fn -> ~t"no trip yet — add #{example = "trip from March 3"}" end)
  end

  # A trip has to start somewhere, and a date is the one fact it cannot be
  # planned without.
  def message(:no_start_date, options) do
    with_locale(options, fn -> ~t"when? — add #{example = "trip from March 3"}" end)
  end

  def message(_reason, _options), do: nil

  defp with_locale(options, fun) do
    locale =
      case Keyword.fetch(options, :locale) do
        {:ok, locale} -> locale
        :error -> Localize.get_locale()
      end

    Gettext.with_locale(LocalizePad.Gettext, gettext_locale(locale), fun)
  end

  defp gettext_locale(locale) do
    case Localize.validate_locale(locale) do
      {:ok, language_tag} -> to_string(language_tag.language)
      {:error, _reason} -> "en"
    end
  end
end
