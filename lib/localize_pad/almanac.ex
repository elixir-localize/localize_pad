defmodule LocalizePad.Almanac do
  @moduledoc """
  Sunrise, sunset, moonrise, moonset and the phase of the moon.

      sunrise                          where you are, today
      sunset tomorrow
      sunrise tomorrow in Chicago
      moonset on December 24, 2026
      moon phase today

  ## Where the coordinates come from

  Astro answers for a latitude and longitude; a person writes a place name. The
  bridge is the timezone database, which the sheet already speaks: `Chicago` is
  resolved to `America/Chicago` by `LocalizePad.Temporal.Zones`, exactly as it
  is in `6pm Sydney in Chicago`, and IANA's own table gives the coordinates of
  the city each zone is named for.

  That table — `priv/almanac/zone.tab`, public domain, shipped with every copy
  of tzdb — is read at compile time. Its precision is the arc-minute or better,
  which is a few seconds of sunrise, and its city is the city the zone means.
  No geocoder, no network, no API key, and the place vocabulary is CLDR's, so
  `Sonnenaufgang in Tokio` needs no second list of names.

  It also means the answer is in the *right clock*. Sunrise in Chicago is
  reported on Chicago's clock, because the same zone that gave the coordinates
  is passed to Astro as the zone to answer in. A time without its zone would be
  a number to convert rather than an answer.

  ## Where you are, when you do not say

  `sunrise` alone has to mean somewhere. The reader's own timezone is the only
  non-arbitrary answer, and the browser knows it — so the page reports it on
  connect and it arrives here as the `:zone` option. Until it does, and where
  the browser will not say, a line naming no place is refused rather than
  answered for a city chosen by this file.

  ## Why the moon's phase is a sentence

  A phase is an angle: 0° is new, 180° is full, and 274.3° is a number no
  reader wanted. The answer is the name of the phase, the emoji Unicode
  provides for it, and how much of the disc is lit — which is the part people
  are actually asking about when they ask.

  """

  alias LocalizePad.{Lexicon, Temporal, Token}

  @typedoc "The events this module answers for."
  @type event :: :sunrise | :sunset | :moonrise | :moonset | :moon_phase

  @type slots :: %{
          date: term() | nil,
          zone: String.t() | nil,
          locale: Localize.LanguageTag.t() | atom() | binary()
        }

  @type node_type :: {:almanac, event(), slots()}

  @table Path.join([:code.priv_dir(:localize_pad), "almanac", "zone.tab"])
  @external_resource @table

  # IANA writes each zone's principal city as ISO 6709: a sign, then degrees
  # and minutes and optionally seconds, run together with no separator —
  # `+415100-0873900` is Chicago. Read once, at compile time, into a map from
  # zone identifier to `{longitude, latitude}` in the order Astro takes them.
  @coordinates (for line <- File.stream!(@table),
                    not String.starts_with?(line, "#"),
                    [_country, point, zone | _comment] = String.split(line, "\t"),
                    into: %{} do
                  {String.trim(zone), LocalizePad.Almanac.Point.parse(point)}
                end)

  @doc """
  Answers a matched line.

  ### Arguments

  * `event` - the event, from `match/2`.

  * `slots` - the date, zone and locale.

  * `options` - a keyword list of options.

  ### Options

  * `:reference_date` - what `today` means. Defaults to the current date in
    the answering zone.

  ### Returns

  * `{:ok, value}` — a `t:DateTime.t/0` on the place's own clock for a rise or
    a set, and a sentence for a phase.

  * `{:error, {:no_location, event}}` when the line named no place and the
    reader's zone is unknown.

  * `{:error, {:unknown_place, name}}` when the line named a place this cannot
    find. Answering for the reader's own city instead would be a confident
    wrong answer to a question that plainly named somewhere else.

  * `{:error, {:no_event, event}}` when there is no such event that day, which
    is an ordinary fact of high latitudes rather than a failure: the sun does
    not rise in a polar winter, and the moon skips a day roughly monthly
    everywhere.

  """
  @spec evaluate(event(), slots(), keyword()) :: {:ok, term()} | {:error, term()}
  def evaluate(event, slots, options \\ [])

  # A phase is the same phase from everywhere the moon is up, so this is the
  # one question that needs no place. Refusing it for want of a location would
  # be refusing to answer something nobody asked about a location.
  def evaluate(:moon_phase, slots, options) do
    with {:ok, moment} <- instant(slots, options) do
      {:ok, describe_phase(moment, slots.locale)}
    end
  end

  def evaluate(_event, %{zone: {:unknown, place}}, _options) do
    {:error, {:unknown_place, place}}
  end

  def evaluate(event, %{zone: nil}, _options), do: {:error, {:no_location, event}}

  def evaluate(event, slots, options) do
    with {:ok, point} <- place(slots.zone),
         {:ok, date} <- date(slots, options) do
      event
      |> compute(point, date, slots.zone)
      |> report(event)
    end
  end

  defp compute(:sunrise, point, date, zone), do: Astro.sunrise(point, date, time_zone: zone)
  defp compute(:sunset, point, date, zone), do: Astro.sunset(point, date, time_zone: zone)
  defp compute(:moonrise, point, date, zone), do: Astro.moonrise(point, date, time_zone: zone)
  defp compute(:moonset, point, date, zone), do: Astro.moonset(point, date, time_zone: zone)

  # Astro distinguishes a polar night from a moon that stays up all day. The
  # sheet does not: each is the same answer to the reader, which is that the
  # event they asked about does not happen there that day.
  defp report({:ok, %DateTime{} = date_time}, _event), do: {:ok, date_time}
  defp report({:error, _reason}, event), do: {:error, {:no_event, event}}

  defp place(zone) do
    case coordinates(zone) do
      {:ok, point} -> {:ok, point}
      :error -> {:error, {:unknown_location, zone}}
    end
  end

  # `today` is a different day either side of the dateline, so it is read on
  # the clock of the place being asked about rather than on this server's.
  defp date(%{date: nil, zone: zone}, options) do
    case Keyword.get(options, :reference_date) do
      nil -> today(zone)
      reference -> {:ok, reference}
    end
  end

  defp date(%{date: fields}, options) do
    with {:ok, resolved} <-
           Temporal.resolve(fields, Keyword.take(options, [:reference_date])),
         {:ok, date} <- Tempo.to_date(resolved) do
      {:ok, date}
    else
      _coarser -> {:error, :not_a_day}
    end
  end

  defp today(zone) do
    case DateTime.now(zone) do
      {:ok, date_time} -> {:ok, DateTime.to_date(date_time)}
      {:error, _reason} -> {:ok, Date.utc_today()}
    end
  end

  # A phase asked about today is asked about now — the moon moves half a degree
  # an hour and the reader can see it. A phase asked about a named day has no
  # such instant, so it is read at noon, the middle of the day rather than
  # either edge of it.
  defp instant(%{date: nil}, options) do
    case Keyword.get(options, :reference_date) do
      nil -> {:ok, DateTime.utc_now()}
      reference -> noon(reference)
    end
  end

  defp instant(slots, options) do
    with {:ok, date} <- date(slots, options) do
      noon(date)
    end
  end

  # UTC has no ambiguous hour and no gap, so the two other things `DateTime`
  # can say about a wall clock cannot arise here. They are folded into the
  # refusal rather than left to escape as a shape the caller never expects.
  defp noon(date) do
    case DateTime.new(date, ~T[12:00:00], "Etc/UTC") do
      {:ok, date_time} -> {:ok, date_time}
      _other -> {:error, :not_a_day}
    end
  end

  # The emoji's sectors, so the name and the picture cannot disagree. Astro
  # picks the emoji by 45° sectors centred on the cardinal phases, which is
  # also where the names belong: a moon 22° past new is still a new moon to
  # look at, and the quarter is a sector rather than an instant nobody's line
  # will land on.
  @phase_names [
    {22.5, "New moon"},
    {67.5, "Waxing crescent"},
    {112.5, "First quarter"},
    {157.5, "Waxing gibbous"},
    {202.5, "Full moon"},
    {247.5, "Waning gibbous"},
    {292.5, "Last quarter"},
    {337.5, "Waning crescent"},
    {360.0, "New moon"}
  ]

  defp describe_phase(moment, locale) do
    phase = Astro.lunar_phase_at(moment)
    lit = Astro.illuminated_fraction_of_moon_at(moment)

    "#{phase_name(phase)} #{Astro.lunar_phase_emoji(phase)} · #{lit_percentage(lit, locale)} lit"
  end

  defp phase_name(phase) do
    {_ceiling, name} = Enum.find(@phase_names, fn {ceiling, _name} -> phase < ceiling end)

    name
  end

  # The number is localized even though the words are not. A German sheet
  # writing `29,9 %` beside an English phase name is half a translation, and
  # the half that is done is the half CLDR does for free.
  defp lit_percentage(fraction, locale) do
    case Localize.Number.to_string(fraction,
           locale: locale,
           format: :percent,
           fractional_digits: 0
         ) do
      {:ok, formatted} -> formatted
      {:error, _reason} -> "#{round(fraction * 100)}%"
    end
  end

  @doc """
  The coordinates of a zone's principal city.

  ### Arguments

  * `zone` - an IANA zone identifier.

  ### Returns

  * `{:ok, {longitude, latitude}}`, in the order Astro takes them.

  * `:error` when the zone is not in IANA's table, which is the case for the
    backward-compatibility links it deliberately leaves out.

  ### Examples

      iex> {:ok, {longitude, latitude}} = LocalizePad.Almanac.coordinates("America/Chicago")
      iex> {Float.round(longitude, 2), Float.round(latitude, 2)}
      {-87.65, 41.85}

      iex> LocalizePad.Almanac.coordinates("Middle/Earth")
      :error

  """
  @spec coordinates(String.t()) :: {:ok, {float(), float()}} | :error
  def coordinates(zone) when is_binary(zone) do
    Map.fetch(@coordinates, zone)
  end

  # The nouns that name an event. English only, as `LocalizePad.Finance` and
  # `LocalizePad.SalesTax` are: the vocabulary of a calculation is the part
  # this application writes rather than the part CLDR supplies, and translating
  # it is a piece of work rather than a line here.
  @nouns %{
    "sunrise" => :sunrise,
    "sunup" => :sunrise,
    "dawn" => :sunrise,
    "sunset" => :sunset,
    "sundown" => :sunset,
    "dusk" => :sunset,
    "moonrise" => :moonrise,
    "moonset" => :moonset,
    "moonphase" => :moon_phase
  }

  # Written as two words more often than one, and the phase is asked for in
  # more ways than it is named.
  @phrases %{
    "moon phase" => :moon_phase,
    "phase of the moon" => :moon_phase,
    "lunar phase" => :moon_phase
  }

  @doc """
  The words this module had to be told.

  TEMPORARY, for a demo — see `LocalizePad.Lexicon.authored/1`.

  ### Returns

  * A list of lowercased forms.

  ### Examples

      iex> "sunrise" in LocalizePad.Almanac.authored()
      true

  """
  @spec authored() :: [String.t()]
  def authored do
    Map.keys(@nouns) ++ ["moon", "phase", "lunar"]
  end

  @doc """
  Recognises a line asking for a sun or moon event.

  ### Arguments

  * `tokens` - the tokens for one line.

  * `options` - a keyword list of options.

  ### Options

  * `:zone` - the reader's own IANA zone, used when the line names no place.

  * `:locale` - the locale the answer is written in.

  ### Returns

  * `{:ok, {:almanac, event, slots}}` when the line names an event.

  * `:error` otherwise, which is the common case — the line is then parsed as
    an ordinary expression.

  ### Examples

      iex> {:ok, tokens} = LocalizePad.Tokenizer.tokenize("sunrise tomorrow in Chicago", locale: :en)
      iex> {:ok, {:almanac, event, slots}} = LocalizePad.Almanac.match(tokens)
      iex> {event, slots.zone}
      {:sunrise, "America/Chicago"}

      iex> {:ok, tokens} = LocalizePad.Tokenizer.tokenize("19 + 22", locale: :en)
      iex> LocalizePad.Almanac.match(tokens)
      :error

  """
  @spec match([Token.t()], keyword()) :: {:ok, node_type()} | :error
  def match(tokens, options \\ []) when is_list(tokens) do
    words = Enum.map(tokens, &(&1.source |> String.trim() |> String.downcase()))

    case event(words) do
      {:ok, event} -> {:ok, {:almanac, event, slots(tokens, options)}}
      :error -> :error
    end
  end

  # A phrase before a noun, because `moon phase` holds a word that is not one
  # of the nouns and would otherwise fall through as prose.
  defp event(words) do
    phrase = Enum.join(words, " ")

    case Enum.find(@phrases, fn {form, _event} -> String.contains?(phrase, form) end) do
      {_form, event} -> {:ok, event}
      nil -> words |> Enum.find_value(&Map.get(@nouns, &1)) |> named()
    end
  end

  defp named(nil), do: :error
  defp named(event), do: {:ok, event}

  # The place named on the line wins over the reader's own, which is the whole
  # point of naming one.
  defp slots(tokens, options) do
    locale = Keyword.get_lazy(options, :locale, &Localize.get_locale/0)

    %{
      date: tokens |> Enum.find(&(&1.kind == :temporal)) |> value(),
      zone: place(tokens, locale) || Keyword.get(options, :zone),
      locale: locale
    }
  end

  defp value(nil), do: nil
  defp value(%Token{value: value}), do: value

  # Three ways a line can say where, in the order they are trusted.
  #
  # A zone token is one the tokenizer already resolved — `Chicago` became
  # `America/Chicago` on the way in, by the same table that reads `6pm Sydney
  # in Chicago`.
  #
  # Otherwise a place is whatever follows `in`, looked up among every city
  # IANA names a zone for. That vocabulary is far wider than the one the rest
  # of the sheet uses, and deliberately so: `Yap` and `Thule` are words that
  # would be dangerous to treat as places in an ordinary note, and are plainly
  # places in a line that has already asked for a sunrise.
  #
  # And a place that cannot be found is `{:unknown, name}` rather than
  # nothing, because nothing would fall through to the reader's own city and
  # answer confidently for Sydney a question that named Longyearbyen.
  defp place(tokens, locale) do
    case Enum.find(tokens, &(&1.kind == :zone)) do
      %Token{value: %{name: name}} -> name
      %Token{value: name} when is_binary(name) -> name
      _no_zone_token -> named_place(tokens, locale)
    end
  end

  defp named_place(tokens, locale) do
    case tokens |> Enum.drop_while(&(not preposition?(&1, locale))) |> Enum.drop(1) do
      [] -> nil
      following -> following |> words() |> lookup(locale)
    end
  end

  # The role, not the word, so `Sonnenaufgang in Tokio` and `lever du soleil à
  # Tokyo` reach this the same way — even though the events themselves are
  # only named in English so far.
  defp preposition?(%Token{kind: :keyword, source: source}, locale) do
    Lexicon.role(String.downcase(source), language(locale)) == {:ok, :to}
  end

  defp preposition?(_token, _locale), do: false

  # `Port Moresby` and `Ho Chi Minh City` are one name in several words, so the
  # longest run wins, exactly as the tokenizer matches multi-word zone names.
  @maximum_place_words 3

  defp words(tokens) do
    tokens
    |> Enum.take(@maximum_place_words)
    |> Enum.take_while(&(&1.kind == :word))
    |> Enum.map(&String.trim(&1.source))
  end

  defp lookup([], _locale), do: nil

  # Matched in lower case and reported as typed. The reader wrote `Atlantis`
  # and the message that comes back should say `Atlantis`.
  defp lookup(words, locale) do
    found =
      Enum.find_value(length(words)..1//-1, fn count ->
        name = words |> Enum.take(count) |> Enum.join(" ") |> String.downcase()

        Map.get(cities(locale), name) || Map.get(cities(:en), name)
      end)

    found || {:unknown, Enum.join(words, " ")}
  end

  # Every city IANA names a zone for, in the reader's own language, built once
  # and kept. `Localize.DateTime.Timezone.exemplar_city/3` derives a name from
  # the identifier where CLDR has none, so this covers the whole table rather
  # than the part CLDR has translated.
  defp cities(locale) do
    key = {__MODULE__, :cities, Localize.Locale.cldr_locale_id_from(locale)}

    case :persistent_term.get(key, nil) do
      nil ->
        built = build_cities(locale)
        :persistent_term.put(key, built)
        built

      built ->
        built
    end
  end

  defp build_cities(locale) do
    for {zone, _point} <- @coordinates,
        {:ok, city} <- [Localize.DateTime.Timezone.exemplar_city(zone, locale)],
        into: %{} do
      {city |> String.trim() |> String.downcase(), zone}
    end
  end

  # The lexicon is keyed by language, so a regional tag reads its parent's
  # vocabulary rather than falling all the way back to English.
  defp language(locale) do
    case Localize.validate_locale(locale) do
      {:ok, tag} -> String.to_existing_atom(to_string(tag.language))
      {:error, _reason} -> :en
    end
  rescue
    ArgumentError -> :en
  end

  @doc """
  The zones this module can place.

  ### Returns

  * A list of IANA identifiers.

  ### Examples

      iex> "Europe/Paris" in LocalizePad.Almanac.zones()
      true

  """
  @spec zones() :: [String.t()]
  def zones, do: Map.keys(@coordinates)
end
