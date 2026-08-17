defmodule LocalizePad.Almanac.Point do
  @moduledoc """
  Reads the ISO 6709 coordinates IANA's zone table is written in.

  A point is a sign, then latitude, then a sign and longitude, run together
  with no separator: `+4230+00131` is Andorra and `+415100-0873900` is Chicago.
  Latitude carries two digits of degrees and longitude three, which is what
  makes the pair separable at all; minutes and seconds follow in fixed pairs,
  and the seconds are optional.

  Its own module because it is parsed at compile time by
  `LocalizePad.Almanac`, and a module cannot call a function it is in the
  middle of defining.

  """

  @doc """
  Parses one ISO 6709 point.

  ### Arguments

  * `point` - the coordinate field of a zone table row.

  ### Returns

  * `{longitude, latitude}` as degrees, in the order Astro takes them.

  ### Examples

      iex> {longitude, latitude} = LocalizePad.Almanac.Point.parse("+4230+00131")
      iex> {Float.round(longitude, 4), Float.round(latitude, 4)}
      {1.5167, 42.5}

      iex> {longitude, latitude} = LocalizePad.Almanac.Point.parse("+353916+1394441")
      iex> {Float.round(longitude, 4), Float.round(latitude, 4)}
      {139.7447, 35.6544}

  """
  @spec parse(String.t()) :: {float(), float()}
  def parse(point) do
    {latitude, longitude} = point |> String.trim() |> split()

    {degrees(longitude), degrees(latitude)}
  end

  # The longitude's sign is the second one, and everything before it is the
  # latitude. Splitting on the sign rather than on a fixed width is what reads
  # `+4230+00131` and `+415100-0873900` with one rule.
  defp split(<<sign::binary-1, rest::binary>>) do
    [degrees, longitude] = String.split(rest, ~r/(?=[-+])/, parts: 2)

    {sign <> degrees, longitude}
  end

  # Degrees, minutes and optionally seconds, in fixed-width pairs after the
  # degrees themselves — which are two digits for a latitude and three for a
  # longitude, so the field's own length says which is which.
  defp degrees(<<sign::binary-1, digits::binary>>) do
    {whole, parts} = String.split_at(digits, if(byte_size(digits) in [4, 6], do: 2, else: 3))

    value =
      parts
      |> chunks()
      |> Enum.with_index(1)
      |> Enum.reduce(String.to_integer(whole), fn {part, index}, degrees ->
        degrees + String.to_integer(part) / :math.pow(60, index)
      end)

    if sign == "-", do: -value, else: value
  end

  defp chunks(""), do: []
  defp chunks(<<pair::binary-2, rest::binary>>), do: [pair | chunks(rest)]
end
