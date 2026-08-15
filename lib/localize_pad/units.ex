defmodule LocalizePad.Units do
  @moduledoc """
  Resolving unit names written in the reader's own language.

  ## The gap this fills

  `Localize.Unit` identifiers are English: `week`, `kilometer`, `mile-per-hour`.
  `Localize.Unit.new(1, "Woche")` fails, and so a German sheet could write
  `1.234,5` correctly and then be unable to say what it was 1234.5 *of*.

  But CLDR knows what a week is called in every locale — that is what
  `display_name/2` is for. Turning that around gives a name-to-identifier index
  per locale, built from data already present, with no vocabulary authored here.
  `3 Wochen` resolves for the same reason `10. Juni` parses: someone at Unicode
  wrote it down and Localize ships it.

  ## Both grammatical numbers

  `display_name/2` returns the plural — "Wochen" — but people write `1 Woche`
  as readily as `3 Wochen`. The singular comes from formatting a quantity of
  *one* and dropping the number, which is the only way to be right in a
  language with more than two plural categories.

  ## English still resolves everywhere

  The index is consulted *after* Unity's alias table, so `km`, `kg` and `mph`
  keep working on a German sheet — SI abbreviations are international, and a
  reader who types them means them.

  ## Prefixed units

  `display_name/2` answers for prefixed identifiers too — `kilometer` is
  "kilomètres" in French and "キロメートル" in Japanese — but the prefixed forms
  are not in CLDR's unit list, so they have to be asked for by name.

  Asking for all of them would mean twenty prefixes against a hundred and
  fifty-five units, most of which nobody writes. The index generates the
  prefixes people use against the units people prefix, which is a couple of
  hundred entries per locale.

  German hid this: "Kilometer" is the identifier `kilometer` but for its
  capital, so it resolved through Unity's table by accident. French and Spanish
  do not have that luck, and `1234,5 mètres en kilomètres` failed until the
  prefixed forms were indexed.

  """

  @doc """
  Resolves a unit name written in the given locale.

  ### Arguments

  * `name` - the unit name as written.

  * `locale` - the locale whose unit vocabulary applies.

  ### Returns

  * `{:ok, identifier}` where identifier is the CLDR unit name.

  * `:error` when the name is not a unit in that locale.

  ### Examples

      iex> LocalizePad.Units.resolve("Wochen", :de)
      {:ok, "week"}

      iex> LocalizePad.Units.resolve("Woche", :de)
      {:ok, "week"}

      iex> LocalizePad.Units.resolve("semaine", :fr)
      {:ok, "week"}

      iex> LocalizePad.Units.resolve("Frühstück", :de)
      :error

  """
  @spec resolve(String.t(), atom()) :: {:ok, String.t()} | :error
  def resolve(name, locale) when is_binary(name) do
    locale
    |> index()
    |> Map.fetch(normalize(name))
  end

  @doc """
  Returns the whole name-to-identifier index for a locale.

  ### Arguments

  * `locale` - the locale to build for.

  ### Returns

  * A map of lowercased display name to CLDR unit identifier.

  ### Examples

      iex> LocalizePad.Units.index(:de) |> Map.get("wochen")
      "week"

  """
  @spec index(atom()) :: %{String.t() => String.t()}
  def index(locale) do
    key = {__MODULE__, :index, locale}

    case :persistent_term.get(key, nil) do
      nil ->
        built = build(locale)
        :persistent_term.put(key, built)
        built

      built ->
        built
    end
  end

  # The prefixes people write, against the units people prefix.
  @prefixes ~w(kilo milli centi micro nano mega giga tera deci hecto)

  @prefixable ~w(
    meter gram liter second byte bit watt joule hertz ampere volt ohm
    pascal newton tonne calorie mole
  )

  defp build(locale) do
    prefixed = for prefix <- @prefixes, unit <- @prefixable, do: prefix <> unit

    Localize.Unit.known_units_by_category()
    |> Map.values()
    |> List.flatten()
    |> Kernel.++(prefixed)
    # Names collide: `week` and `week-person` are both "Wochen" in German. The
    # simpler identifier is what someone writing "Wochen" means, so process
    # units simplest-first and never overwrite.
    |> Enum.sort_by(&{String.split(&1, "-") |> length(), String.length(&1)})
    |> Enum.reduce(%{}, fn unit, index ->
      unit
      |> names_for(locale)
      |> Enum.reduce(index, fn {name, identifier}, acc ->
        Map.put_new(acc, name, identifier)
      end)
    end)
  end

  # A unit contributes its plural display name and its singular form. Names
  # shorter than three characters are dropped: they are abbreviations that
  # collide with ordinary words far more often than they help, and Unity's
  # alias table already covers the ones worth having.
  defp names_for(unit, locale) do
    [display_name(unit, locale), singular(unit, locale)]
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&(String.length(&1) >= 3))
    |> Enum.map(&{normalize(&1), unit})
    |> Enum.uniq()
  end

  defp display_name(unit, locale) do
    case Localize.Unit.display_name(unit, locale: locale) do
      {:ok, name} -> name
      _other -> nil
    end
  end

  defp singular(unit, locale) do
    with {:ok, quantity} <- Localize.Unit.new(1, unit),
         {:ok, formatted} <- Localize.Unit.to_string(quantity, locale: locale),
         {:ok, one} <- Localize.Number.to_string(1, locale: locale) do
      formatted |> String.replace_prefix(one, "") |> String.trim()
    else
      _other -> nil
    end
  end

  defp normalize(name), do: name |> String.trim() |> String.downcase()
end
