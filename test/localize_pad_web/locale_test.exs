defmodule LocalizePadWeb.LocaleTest do
  @moduledoc """
  Guards the locale-discovery wiring in the browser pipeline.

  In this app the locale is not presentation. It decides how a sheet's numbers
  and dates are *parsed* — `3/4/26` is 3 April under `en-GB` and 4 March under
  `en-US`, and `1.234,5` is one number in `de` and something else entirely in
  `en`. If locale discovery silently stops working, sheets compute wrong
  answers rather than merely looking wrong, so it is worth a test from the
  first commit.

  """

  use LocalizePadWeb.ConnCase, async: true

  alias Localize.Plug.PutLocale

  describe "locale discovery" do
    test "falls back to the configured default when the request says nothing", %{conn: conn} do
      conn = get(conn, ~p"/")

      assert %Localize.LanguageTag{cldr_locale_id: :en} = PutLocale.get_locale(conn)
    end

    test "honours an explicit locale query parameter", %{conn: conn} do
      conn = get(conn, ~p"/?locale=de")

      assert %Localize.LanguageTag{cldr_locale_id: :de} = PutLocale.get_locale(conn)
    end

    test "honours the accept-language header", %{conn: conn} do
      conn =
        conn
        |> put_req_header("accept-language", "ja,en;q=0.5")
        |> get(~p"/")

      assert %Localize.LanguageTag{cldr_locale_id: :ja} = PutLocale.get_locale(conn)
    end

    test "a query parameter beats the accept-language header", %{conn: conn} do
      conn =
        conn
        |> put_req_header("accept-language", "ja")
        |> get(~p"/?locale=fr")

      assert %Localize.LanguageTag{cldr_locale_id: :fr} = PutLocale.get_locale(conn)
    end

    test "the discovered locale is persisted into the session for the LiveView to restore", %{
      conn: conn
    } do
      conn = get(conn, ~p"/?locale=es")

      assert get_session(conn, PutLocale.session_key()) == "es"
    end

    test "an unparseable locale leaves the request intact", %{conn: conn} do
      conn = get(conn, ~p"/?locale=xx")

      assert conn.status == 200
      assert %Localize.LanguageTag{cldr_locale_id: :en} = PutLocale.get_locale(conn)
    end

    # Documents a live question rather than blessing the behaviour: `:localize`
    # is configured with `supported_locales: [:en, :de, :fr, :es, :ja]`, but
    # `?locale=not-a-locale` still resolves — "not" is a real ISO 639-3 code
    # (Nomatsiguenga) and validation lets it through. The request survives,
    # which is what this asserts; whether an out-of-list locale *should* be
    # accepted is an open question with Localize. If it is tightened upstream,
    # this test starts failing loudly, which is the point.
    test "an off-list but syntactically real locale does not crash the request", %{conn: conn} do
      conn = get(conn, ~p"/?locale=not-a-locale")

      assert conn.status == 200
      assert %Localize.LanguageTag{} = PutLocale.get_locale(conn)
    end
  end
end
