defmodule LocalizePad.Temporal.Zones do
  @moduledoc """
  Resolves the names people actually type — `Sydney`, `LAX`, `PST`, `Japan` —
  into IANA time zones.

  ## Why a curated list rather than every IANA city

  IANA ships 597 zones, and taking the last path segment of each would give a
  city index for free. It would also give `Truk`, `Thule`, `Yap`, and a long
  tail of names that collide with ordinary words in ordinary notes. In a
  language whose defining rule is that unrecognised words are noise, a word
  that silently becomes a *value* is far more damaging than one that stays
  noise — the same reasoning that governs the date shape filter in
  `LocalizePad.Temporal.Scanner`.

  So the city table below is curated to the large cities people write down,
  which is also what Soulver documents itself as supporting. Extending it is a
  data edit.

  ## A zone is never a value on its own

  `Sydney` alone is not a time. Only `6pm Sydney`, or a conversion target in
  `… in Chicago`, means anything, and the evaluator declines a bare zone. That
  keeps `flight to Paris` an ordinary note rather than a clock reading.

  ## What is delegated

  Zone abbreviations (`PST`, `JST`), IANA identifiers, GMT offsets and CLDR
  localized zone names (`Pacific Time`, `Mitteleuropäische Zeit`) are all
  handled by `Calendrical.TimeZone.resolve/3`. This module adds only the
  layers CLDR has no answer for: bare city names and airport codes.

  """

  alias LocalizePad.Locales

  defstruct [:name]

  @type t :: %__MODULE__{name: String.t()}

  # Cities large enough that someone writes them in a note expecting a clock
  # reading. Keyed by the lowercased name so lookup is case-insensitive.
  # The zones this module will name. Curation is the point: IANA ships 597, and
  # taking the last segment of each would give `Truk`, `Thule` and `Yap` — words
  # that collide with ordinary notes. Which zones are worth naming is a product
  # judgement and stays here.
  #
  # What their *names* are is not. Every name comes from
  # `Localize.DateTime.Timezone.exemplar_city/3`, which returns the locale's own
  # exemplar city and falls back to deriving one from the identifier, exactly as
  # TR35 prescribes. That is what makes `Tokio` work on a German sheet and
  # `Londres` on a French one without a word of it being written down here.
  @zones [
    "Africa/Cairo",
    "Africa/Johannesburg",
    "Africa/Lagos",
    "Africa/Nairobi",
    "America/Argentina/Buenos_Aires",
    "America/Bogota",
    "America/Chicago",
    "America/Denver",
    "America/Lima",
    "America/Los_Angeles",
    "America/Mexico_City",
    "America/New_York",
    "America/Santiago",
    "America/Sao_Paulo",
    "America/Toronto",
    "America/Vancouver",
    "Asia/Bangkok",
    "Asia/Dubai",
    "Asia/Ho_Chi_Minh",
    "Asia/Hong_Kong",
    "Asia/Jakarta",
    "Asia/Jerusalem",
    "Asia/Karachi",
    "Asia/Kolkata",
    "Asia/Manila",
    "Asia/Riyadh",
    "Asia/Seoul",
    "Asia/Shanghai",
    "Asia/Singapore",
    "Asia/Taipei",
    "Asia/Tehran",
    "Asia/Tokyo",
    "Atlantic/Reykjavik",
    "Australia/Brisbane",
    "Australia/Melbourne",
    "Australia/Perth",
    "Australia/Sydney",
    "Europe/Amsterdam",
    "Europe/Athens",
    "Europe/Berlin",
    "Europe/Brussels",
    "Europe/Copenhagen",
    "Europe/Dublin",
    "Europe/Helsinki",
    "Europe/Istanbul",
    "Europe/Kyiv",
    "Europe/Lisbon",
    "Europe/London",
    "Europe/Madrid",
    "Europe/Moscow",
    "Europe/Oslo",
    "Europe/Paris",
    "Europe/Prague",
    "Europe/Rome",
    "Europe/Stockholm",
    "Europe/Vienna",
    "Europe/Warsaw",
    "Europe/Zurich",
    "Pacific/Auckland",
    "Pacific/Honolulu"
  ]

  # Names that are not the zone's own city: another city sharing the zone, or a
  # form written without its accents. CLDR cannot supply these because they are
  # not what the zone is called — `Asia/Shanghai` is Shanghai, and somebody
  # writing `Beijing` still means that clock.
  @aliases %{
    "beijing" => "Asia/Shanghai",
    "bogota" => "America/Bogota",
    "boston" => "America/New_York",
    "dallas" => "America/Chicago",
    "delhi" => "Asia/Kolkata",
    "frankfurt" => "Europe/Berlin",
    "hanoi" => "Asia/Ho_Chi_Minh",
    "houston" => "America/Chicago",
    "kiev" => "Europe/Kyiv",
    "miami" => "America/New_York",
    "milan" => "Europe/Rome",
    "montreal" => "America/Toronto",
    "mumbai" => "Asia/Kolkata",
    "munich" => "Europe/Berlin",
    "rio de janeiro" => "America/Sao_Paulo",
    "san francisco" => "America/Los_Angeles",
    "sao paulo" => "America/Sao_Paulo",
    "seattle" => "America/Los_Angeles",
    "tel aviv" => "Asia/Jerusalem",
    "wellington" => "Pacific/Auckland"
  }

  # Countries, using the capital's zone where the country spans several — the
  # convention Soulver documents.
  @countries %{
    "argentina" => "America/Argentina/Buenos_Aires",
    "australia" => "Australia/Sydney",
    "brazil" => "America/Sao_Paulo",
    "canada" => "America/Toronto",
    "china" => "Asia/Shanghai",
    "france" => "Europe/Paris",
    "germany" => "Europe/Berlin",
    "india" => "Asia/Kolkata",
    "ireland" => "Europe/Dublin",
    "italy" => "Europe/Rome",
    "japan" => "Asia/Tokyo",
    "mexico" => "America/Mexico_City",
    "netherlands" => "Europe/Amsterdam",
    "new zealand" => "Pacific/Auckland",
    "norway" => "Europe/Oslo",
    "poland" => "Europe/Warsaw",
    "russia" => "Europe/Moscow",
    "singapore" => "Asia/Singapore",
    "spain" => "Europe/Madrid",
    "sweden" => "Europe/Stockholm",
    "switzerland" => "Europe/Zurich",
    "thailand" => "Asia/Bangkok",
    "turkey" => "Europe/Istanbul",
    "uk" => "Europe/London",
    "usa" => "America/New_York"
  }

  # Airport codes, which people use as shorthand for a city rather than an
  # airport: `7:30am LAX`.
  @airports %{
    "ams" => "Europe/Amsterdam",
    "atl" => "America/New_York",
    "bkk" => "Asia/Bangkok",
    "bos" => "America/New_York",
    "cdg" => "Europe/Paris",
    "dfw" => "America/Chicago",
    "dub" => "Europe/Dublin",
    "dxb" => "Asia/Dubai",
    "fco" => "Europe/Rome",
    "fra" => "Europe/Berlin",
    "hkg" => "Asia/Hong_Kong",
    "hnd" => "Asia/Tokyo",
    "iad" => "America/New_York",
    "ist" => "Europe/Istanbul",
    "jfk" => "America/New_York",
    "lax" => "America/Los_Angeles",
    "lhr" => "Europe/London",
    "mel" => "Australia/Melbourne",
    "mex" => "America/Mexico_City",
    "mia" => "America/New_York",
    "muc" => "Europe/Berlin",
    "nrt" => "Asia/Tokyo",
    "ord" => "America/Chicago",
    "sfo" => "America/Los_Angeles",
    "sin" => "Asia/Singapore",
    "syd" => "Australia/Sydney",
    "yyz" => "America/Toronto",
    "zrh" => "Europe/Zurich"
  }

  @doc """
  Resolves a name to a zone.

  ### Arguments

  * `name` - a city, country, airport code, zone abbreviation or IANA
    identifier.

  ### Returns

  * `{:ok, zone}` where zone is a `t:LocalizePad.Temporal.Zones.t/0`.

  * `:error` when the name is not a zone — which is the common case, since
    most words are not.

  ### Examples

      iex> LocalizePad.Temporal.Zones.resolve("Sydney")
      {:ok, %LocalizePad.Temporal.Zones{name: "Australia/Sydney"}}

      iex> LocalizePad.Temporal.Zones.resolve("LAX")
      {:ok, %LocalizePad.Temporal.Zones{name: "America/Los_Angeles"}}

      iex> LocalizePad.Temporal.Zones.resolve("breakfast")
      :error

  """
  @spec resolve(String.t(), Locales.locale()) :: {:ok, t()} | :error
  def resolve(name, locale \\ :en) when is_binary(name) do
    key = name |> String.trim() |> String.downcase()

    # The reader's own names first, then the identifier-derived ones. A German
    # sheet should understand `Tokio`, and it should not stop understanding
    # `Tokyo` — the IANA name is what half the world's software prints, and
    # somebody pasting a booking confirmation is not switching locale first.
    with :error <- Map.fetch(cities(locale), key),
         :error <- Map.fetch(cities(:en), key),
         :error <- Map.fetch(@aliases, key),
         :error <- Map.fetch(countries(locale), key),
         :error <- Map.fetch(countries(:en), key),
         :error <- Map.fetch(@countries, key),
         :error <- Map.fetch(@airports, key) do
      via_calendrical(name)
    else
      {:ok, zone} -> {:ok, %__MODULE__{name: zone}}
    end
  end

  # City name to zone, in the reader's language, built once per locale. English
  # is not a special case: `London` reaches this the same way `Londres` does,
  # because `exemplar_city/3` derives a name from the identifier wherever CLDR
  # has none — which is most of them, English included.
  defp cities(locale) do
    id = Localize.Locale.cldr_locale_id_from(locale)
    key = {__MODULE__, :cities, id}

    case :persistent_term.get(key, nil) do
      nil ->
        built = build_cities(locale)
        :persistent_term.put(key, built)
        built

      built ->
        built
    end
  end

  # A country name means a zone only where the country *has* one zone. `Japan`
  # is unambiguous and `Vereinigtes Königreich` is too; the United States has
  # twenty-nine and Australia twelve, so naming either says nothing about which
  # clock. That is the same test CLDR applies when it chooses between a country
  # name and a city for a zone's display name.
  defp countries(locale) do
    id = Localize.Locale.cldr_locale_id_from(locale)
    key = {__MODULE__, :countries, id}

    case :persistent_term.get(key, nil) do
      nil ->
        built = build_countries(locale)
        :persistent_term.put(key, built)
        built

      built ->
        built
    end
  end

  defp build_countries(locale) do
    territories = Localize.DateTime.Timezone.territories_by_timezone()

    for zone <- @zones,
        territory = Map.get(territories, zone),
        territory != nil,
        Localize.DateTime.Timezone.timezone_count_for_territory(territory) == {:ok, 1},
        {:ok, name} <- [Localize.Territory.display_name(territory, locale: locale)],
        into: %{} do
      {name |> String.trim() |> String.downcase(), zone}
    end
  end

  defp build_cities(locale) do
    for zone <- @zones,
        {:ok, city} <- [Localize.DateTime.Timezone.exemplar_city(zone, locale)],
        into: %{} do
      {city |> String.trim() |> String.downcase(), zone}
    end
  end

  # Names shaped like a zone identifier rather than an English word: an
  # all-caps abbreviation (`PST`, `JST`), an IANA path (`Asia/Tokyo`), a GMT
  # offset, or a CLDR zone name (`Pacific Time`).
  #
  # The shape test matters for cost as much as for correctness — without it,
  # every word of every line would be handed to the zone resolver.
  @zone_shaped ~r/^([A-Z]{2,5}|.+\/.+|(GMT|UTC)[-+].+|.*\bTime)$/u

  defp via_calendrical(name) do
    if Regex.match?(@zone_shaped, name) do
      case Calendrical.TimeZone.resolve(name, NaiveDateTime.utc_now()) do
        {:ok, %DateTime{time_zone: zone}} -> {:ok, %__MODULE__{name: zone}}
        _other -> :error
      end
    else
      :error
    end
  end

  @doc """
  Returns every name this module recognises.

  Used by the tokenizer to match multi-word names such as `New York` before
  their individual words are classified.

  ### Returns

  * A list of lowercased names, longest first.

  ### Examples

      iex> "new york" in LocalizePad.Temporal.Zones.known_names()
      true

  """
  @spec known_names() :: [String.t()]
  def known_names do
    key = {__MODULE__, :known_names}

    case :persistent_term.get(key, nil) do
      nil ->
        names =
          [cities(:en), @aliases, @countries, @airports]
          |> Enum.flat_map(&Map.keys/1)
          |> Enum.uniq()
          |> Enum.sort_by(&(-String.length(&1)))

        :persistent_term.put(key, names)
        names

      names ->
        names
    end
  end
end
