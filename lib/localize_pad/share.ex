defmodule LocalizePad.Share do
  @moduledoc """
  Encoding a sheet into a link, so it can be shown to someone without an
  account existing on either end.

  ## The whole sheet travels in the URL fragment

  Not a query string, and not a row in a table. A fragment is never sent in an
  HTTP request, so a shared sheet does not pass through the server's access
  logs, a proxy, or a referrer header on the way to whoever opens it. Nothing
  is stored, so nothing needs deleting, and a link cannot rot because there is
  no record behind it to lose.

  The cost is length. A sheet is gzipped before encoding, which measured
  against real sheets comes out at roughly a quarter to a third of the source
  once there is anything to compress — a forty-line sheet of 1,372 characters
  makes a 419-character link.

  Below about a hundred characters gzip's header and base64's third cost more
  than the compression saves, and a very short sheet produces a link longer
  than its own text. That is not worth fixing: the links are tiny either way,
  and a rule that sometimes skipped compression would need a flag in the
  payload to say which it did.

  A very long sheet will eventually make an unwieldy link. Downloading the
  Markdown is the answer at that size.

  ## The locale travels with it

  `1.234,5` is a different number in `de` than in `en`. A link that carried
  only the text would show the recipient different answers from the sender,
  which is worse than not sharing at all.

  """

  @separator "~"

  @doc """
  Encodes a sheet's source and locale into a fragment-safe string.

  ### Arguments

  * `source` - the sheet's text.

  * `locale` - the locale it should be read in.

  ### Returns

  * A URL-safe string.

  ### Examples

      iex> encoded = LocalizePad.Share.encode("19 + 22", :en)
      iex> LocalizePad.Share.decode(encoded)
      {:ok, "19 + 22", :en}

  """
  @spec encode(String.t(), atom()) :: String.t()
  def encode(source, locale) when is_binary(source) do
    payload = to_string(locale) <> @separator <> source

    payload
    |> :zlib.gzip()
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Decodes a shared sheet.

  ### Arguments

  * `encoded` - the fragment value from `encode/2`.

  ### Returns

  * `{:ok, source, locale}` when the value is a sheet this application wrote.

  * `:error` for anything else. A link is untrusted input — it may be
    truncated by a chat client, mangled by a mail client, or simply made up —
    so a bad one opens an empty sheet rather than failing the page.

  ### Examples

      iex> LocalizePad.Share.decode("not a real payload")
      :error

  """
  @spec decode(String.t()) :: {:ok, String.t(), atom()} | :error
  def decode(encoded) when is_binary(encoded) do
    with {:ok, compressed} <- Base.url_decode64(encoded, padding: false),
         {:ok, payload} <- gunzip(compressed),
         [locale, source] <- String.split(payload, @separator, parts: 2),
         {:ok, language_tag} <- Localize.validate_locale(locale) do
      {:ok, source, language_tag.cldr_locale_id}
    else
      _not_a_sheet -> :error
    end
  end

  def decode(_encoded), do: :error

  # `:zlib.gunzip/1` raises on anything that is not gzip, and this is fed
  # directly from a URL.
  defp gunzip(compressed) do
    {:ok, :zlib.gunzip(compressed)}
  rescue
    _exception -> :error
  end
end
