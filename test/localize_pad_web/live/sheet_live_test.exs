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

  describe "the detail panel" do
    # A margin one line high cannot hold a set of dates, so it truncates. The
    # panel is where the whole answer lives.
    test "clicking a set answer shows every value, not the summary" do
      {:ok, live, _html} = live(build_conn(), ~p"/")

      render_change(live, :edit, %{"source" => "every Friday the 13th in 2027"})
      html = render_click(live, :select, %{"line" => "0"})

      assert html =~ "Aug 13, 2027"
      assert html =~ "temporal_set"
    end

    test "a recurrence with more dates than the margin holds shows all of them" do
      {:ok, live, _html} = live(build_conn(), ~p"/")

      render_change(live, :edit, %{"source" => "every Monday"})
      summary = render(live)
      detail = render_click(live, :select, %{"line" => "0"})

      # The margin shows a count and drops the tail; the panel keeps it. The
      # fifth Monday is the one the summary cannot fit, so it is the one worth
      # asserting on — checking merely that the panel has no ellipsis would
      # pass on a page that still shows the truncated margin above it.
      fifth = summary |> fifth_monday()

      assert summary =~ "5 dates"
      refute summary =~ fifth
      assert detail =~ fifth
    end

    # The fifth Monday from today, formatted the way the sheet formats it.
    defp fifth_monday(_summary) do
      today = Date.utc_today()
      first = Date.add(today, Integer.mod(1 - Date.day_of_week(today), 7))

      {:ok, formatted} =
        Localize.Date.to_string(Date.add(first, 28), locale: :en, format: :medium)

      formatted
    end

    test "clicking the open line closes the panel" do
      {:ok, live, _html} = live(build_conn(), ~p"/")

      render_change(live, :edit, %{"source" => "2 + 2"})
      opened = render_click(live, :select, %{"line" => "0"})
      closed = render_click(live, :select, %{"line" => "0"})

      assert opened =~ "2 + 2"
      refute closed =~ "number"
    end

    test "a line with no answer cannot be selected" do
      {:ok, live, _html} = live(build_conn(), ~p"/")

      render_change(live, :edit, %{"source" => "# just a heading"})
      html = render_click(live, :select, %{"line" => "0"})

      refute html =~ "heading</code>"
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
