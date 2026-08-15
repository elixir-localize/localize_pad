defmodule LocalizePadWeb.SheetLiveTest do
  use LocalizePadWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "mounting" do
    test "renders the sheet with its answers", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/")

      assert html =~ "LocalizePad"
      assert html =~ "9.84252 feet"
      assert html =~ "96.56064 kilometers per hour"
    end

    test "shows a running total", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/")

      assert html =~ "Total"
    end
  end

  describe "editing" do
    test "typing recalculates" do
      {:ok, live, _html} = live(build_conn(), ~p"/")

      html = render_change(live, :edit, %{"source" => "19 + 22"})

      assert html =~ "41"
    end

    test "a line that cannot be evaluated leaves the others working" do
      {:ok, live, _html} = live(build_conn(), ~p"/")

      html = render_change(live, :edit, %{"source" => "2 +\n19 + 22"})

      assert html =~ "41"
    end

    test "an empty sheet does not break the page" do
      {:ok, live, _html} = live(build_conn(), ~p"/")

      assert render_change(live, :edit, %{"source" => ""})
    end
  end

  describe "the locale picker re-reads the sheet" do
    # This is the product in one test. The same characters produce different
    # arithmetic and a different rendering, because the locale governs how the
    # text is parsed rather than only how the answer is printed.
    test "the same text means different numbers in different locales" do
      {:ok, live, _html} = live(build_conn(), ~p"/")

      render_change(live, :edit, %{"source" => "1.234,5 + 1"})

      german = render_change(live, :set_locale, %{"locale" => "de"})
      assert german =~ "1.235,5"

      english = render_change(live, :set_locale, %{"locale" => "en"})
      refute english =~ "1.235,5"
    end

    test "unit names follow the locale" do
      {:ok, live, _html} = live(build_conn(), ~p"/")

      render_change(live, :edit, %{"source" => "3 meters"})

      assert render_change(live, :set_locale, %{"locale" => "de"}) =~ "3 Meter"
      assert render_change(live, :set_locale, %{"locale" => "en"}) =~ "3 meters"
    end

    test "the picker names each locale in its own language" do
      {:ok, _live, html} = live(build_conn(), ~p"/")

      assert html =~ "Deutsch"
      assert html =~ "Français"
      assert html =~ "日本語"
    end

    test "an unknown locale leaves the sheet alone" do
      {:ok, live, _html} = live(build_conn(), ~p"/")

      render_change(live, :edit, %{"source" => "3 meters"})

      # `zz` is not a language subtag at all, so validation rejects it and the
      # sheet keeps reading as English. Nothing the picker can send should be
      # able to change how a document is interpreted without being a locale.
      html = render_change(live, :set_locale, %{"locale" => "zz-junk"})

      assert html =~ "3 meters"
      refute html =~ "3 Meter<"
    end
  end
end
