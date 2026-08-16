defmodule LocalizePad.ShareTest do
  use ExUnit.Case, async: true

  alias LocalizePad.{Share, Sheet}

  doctest LocalizePad.Share

  describe "round-tripping a sheet" do
    test "source and locale both survive" do
      source = "# Trip\n\n19 + 22\nhotel = 120 EUR"

      assert {:ok, ^source, locale} = source |> Share.encode(:de) |> Share.decode()
      assert to_string(locale) == "de"
    end

    test "a sheet decoded from a link computes what the sender saw" do
      # The locale travels with the text because `1.234,5` is a different
      # number in `de` than in `en`. A link carrying only the text would show
      # the recipient different answers, which is worse than not sharing.
      {:ok, source, locale} = "1.234,5 + 1" |> Share.encode(:de) |> Share.decode()

      assert [%{formatted: "1.235,5"}] = Sheet.new(source, locale: locale).lines
    end

    test "newlines, unicode and the sheet's own syntax survive" do
      source = "# 日本語\n\n100キロメートルをマイルで\n// a comment\n@1 + 1"

      assert {:ok, ^source, locale} = source |> Share.encode(:ja) |> Share.decode()
      assert to_string(locale) == "ja"
    end

    test "the payload is URL-safe" do
      encoded = Share.encode(String.duplicate("19 + 22 for breakfast\n", 20), :en)

      assert encoded == URI.encode(encoded)
      refute String.contains?(encoded, ["+", "/", "="])
    end
  end

  describe "a link is untrusted input" do
    # It may be truncated by a chat client, mangled by a mail client, or made
    # up. None of those should fail the page.
    test "nonsense decodes to an error rather than raising" do
      assert Share.decode("not a real payload") == :error
      assert Share.decode("") == :error
      assert Share.decode(nil) == :error
    end

    test "a truncated payload is an error" do
      encoded = Share.encode("19 + 22", :en)

      assert Share.decode(String.slice(encoded, 0, 20)) == :error
    end

    test "valid base64 that is not a sheet is an error" do
      assert Share.decode(Base.url_encode64("hello", padding: false)) == :error
    end

    test "a payload naming a locale that does not exist is an error" do
      payload = "zz-junk~19 + 22" |> :zlib.gzip() |> Base.url_encode64(padding: false)

      assert Share.decode(payload) == :error
    end
  end
end
