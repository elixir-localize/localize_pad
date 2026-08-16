defmodule LocalizePad.Currency do
  @moduledoc """
  Recognises currency symbols and codes in a line.

  ## Why not `Money.parse/2`

  Money will happily parse a bare number: `Money.parse("19")` returns
  19 US dollars. That is right for a field labelled "price" and catastrophic
  here, where it would turn every number in every sheet into money.

  So currency is only recognised when it is *written* — a symbol like `$` or
  `€`, or an ISO code like `USD`. A number on its own stays a number.

  ## `$` follows the reader

  `$` means Australian dollars to someone writing in `en-AU` and US dollars in
  `en-US`, which is the behaviour Soulver ties to your Mac's region settings.
  `Localize.Currency.currency_from_locale/1` supplies it from CLDR, so it
  costs nothing and works for every locale rather than a handful.

  ## Codes must be written in capitals

  Several ISO codes are also ordinary English words — `ALL` (Albanian lek),
  `TRY` (Turkish lira), `CUP` (Cuban peso, and also a unit of volume). Requiring
  the code to appear in capitals is what keeps `2 cup of flour` from becoming
  Cuban pesos. It is a heuristic, but the failure mode is a missed currency
  rather than an invented one.

  """

  alias LocalizePad.Locales

  # Symbols that name a currency outright. `$` is deliberately absent: it
  # depends on the locale and is resolved separately.
  @symbols %{
    "€" => :EUR,
    "£" => :GBP,
    "¥" => :JPY,
    "₹" => :INR,
    "₽" => :RUB,
    "₩" => :KRW,
    "₪" => :ILS,
    "₺" => :TRY,
    "₫" => :VND,
    "₴" => :UAH,
    "₦" => :NGN,
    "฿" => :THB,
    "US$" => :USD,
    "A$" => :AUD,
    "AU$" => :AUD,
    "C$" => :CAD,
    "CA$" => :CAD,
    "NZ$" => :NZD,
    "S$" => :SGD,
    "HK$" => :HKD,
    "NT$" => :TWD,
    "R$" => :BRL
  }

  @doc """
  Resolves a written currency marker to an ISO code.

  ### Arguments

  * `marker` - a symbol such as `€`, a prefixed symbol such as `A$`, or an
    ISO code in capitals such as `USD`.

  * `locale` - the locale that decides what a bare `$` means.

  ### Returns

  * `{:ok, code}` where code is a currency atom.

  * `:error` when the marker names no currency.

  ### Examples

      iex> LocalizePad.Currency.resolve("€", :en)
      {:ok, :EUR}

      iex> LocalizePad.Currency.resolve("$", :en)
      {:ok, :USD}

      iex> LocalizePad.Currency.resolve("$", :"en-AU")
      {:ok, :AUD}

      iex> LocalizePad.Currency.resolve("cup", :en)
      :error

  """
  @spec resolve(String.t(), atom()) :: {:ok, atom()} | :error
  def resolve(marker, locale \\ :en) when is_binary(marker) do
    cond do
      marker == "$" -> dollar(locale)
      Map.has_key?(@symbols, marker) -> Map.fetch(@symbols, marker)
      true -> code(marker)
    end
  end

  @doc """
  Whether a marker names a currency.

  ### Arguments

  * `marker` - the text to test.

  * `locale` - the locale that decides what a bare `$` means.

  ### Returns

  * `true` or `false`.

  ### Examples

      iex> LocalizePad.Currency.currency?("USD", :en)
      true

      iex> LocalizePad.Currency.currency?("breakfast", :en)
      false

  """
  @spec currency?(String.t(), atom()) :: boolean()
  def currency?(marker, locale \\ :en) do
    match?({:ok, _code}, resolve(marker, locale))
  end

  @doc """
  Resolves a currency written by name in the reader's language.

  ### Arguments

  * `name` - the name as written, such as `Australian dollar` or
    `Australischer Dollar`.

  * `locale` - the locale whose currency names apply.

  ### Returns

  * `{:ok, code}` or `:error`.

  ### Examples

      iex> LocalizePad.Currency.resolve_name("australian dollar", :en)
      {:ok, :AUD}

      iex> LocalizePad.Currency.resolve_name("australischer dollar", :de)
      {:ok, :AUD}

      iex> LocalizePad.Currency.resolve_name("breakfast", :en)
      :error

  """
  @spec resolve_name(String.t(), Locales.locale()) :: {:ok, atom()} | :error
  def resolve_name(name, locale) when is_binary(name) do
    Map.fetch(names(locale), normalize(name))
  end

  @doc """
  Every currency name this locale knows, longest first.

  Used by the tokenizer to match `Australian dollar` before its words are
  classified separately.

  ### Arguments

  * `locale` - the locale whose currency names apply.

  ### Returns

  * A list of lowercased names.

  ### Examples

      iex> "australian dollar" in LocalizePad.Currency.known_names(:en)
      true

  """
  @spec known_names(Locales.locale()) :: [String.t()]
  def known_names(locale) do
    locale |> names() |> Map.keys() |> Enum.sort_by(&(-String.length(&1)))
  end

  # Name to code, from CLDR's own currency names — the display name and both
  # plural forms, so `Australian dollar` and `Australian dollars` both resolve.
  # Nothing here is authored; the same data renders the answer.
  defp names(locale) do
    id = Localize.Locale.cldr_locale_id_from(locale)
    key = {__MODULE__, :names, id}

    case :persistent_term.get(key, nil) do
      nil ->
        built = build_names(locale)
        :persistent_term.put(key, built)
        built

      built ->
        built
    end
  end

  defp build_names(locale) do
    case Localize.Locale.get(locale, [:currencies]) do
      {:ok, currencies} ->
        for {code, currency} <- currencies,
            currency.tender,
            name <- [currency.name | Map.values(currency.count || %{})],
            is_binary(name),
            into: %{} do
          {normalize(name), code}
        end

      _absent ->
        %{}
    end
  end

  defp normalize(name), do: name |> String.trim() |> String.downcase()

  # `$` means the reader's own dollar — but only where the reader's currency is
  # actually written `$`. That holds for the US, Australia, Canada, Singapore
  # and a dozen others, and it does not hold for Britain, Germany or Japan: a
  # reader there who types `$300` means dollars, and answering `£300` or
  # `€300` is a wrong number rather than a localized one.
  #
  # CLDR's *narrow* symbol is what decides it, because the standard symbol
  # disambiguates between currencies that share one — `A$` for Australia — and
  # would reject the very locales this is meant to serve.
  defp dollar(locale) do
    with {:ok, currency} <- Localize.Currency.currency_from_locale(locale),
         {:ok, "$"} <- Localize.Currency.symbol(currency, :narrow) do
      {:ok, currency}
    else
      # A locale whose money is not a dollar still has to mean something by
      # `$`, and the US dollar is the least surprising reading.
      _not_a_dollar -> {:ok, :USD}
    end
  end

  # Capitals only — see the moduledoc on why `cup` must not become `CUP`.
  defp code(marker) do
    if marker == String.upcase(marker) and String.length(marker) == 3 do
      validate(marker)
    else
      :error
    end
  end

  defp validate(marker) do
    case Money.validate_currency(marker) do
      {:ok, currency} -> {:ok, currency}
      {:error, _reason} -> :error
    end
  rescue
    # `validate_currency/1` converts to an atom internally; an unknown code
    # must not take a sheet down.
    _exception -> :error
  end
end
