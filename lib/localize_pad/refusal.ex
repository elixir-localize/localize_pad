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
  def message({:no_event, event}, options) when is_atom(event) do
    with_locale(options, fn -> ~t"no #{name = to_string(event)} there that day" end)
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
