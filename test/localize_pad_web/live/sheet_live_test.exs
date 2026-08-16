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

      # The kind label only appears in the panel; `tok-number` classes from the
      # highlighter are on the page either way, so match the panel's own markup.
      assert opened =~ ~s(<span class="shrink-0 opacity-40">number</span>)
      refute closed =~ ~s(<span class="shrink-0 opacity-40">number</span>)
    end

    test "a line with no answer cannot be selected" do
      {:ok, live, _html} = live(build_conn(), ~p"/")

      render_change(live, :edit, %{"source" => "# just a heading"})
      html = render_click(live, :select, %{"line" => "0"})

      refute html =~ "heading</code>"
    end
  end

  describe "the line-number gutter" do
    defp gutter(html) do
      html
      |> String.split(~r{<pre id="gutter".*?>}, parts: 2)
      |> List.last()
      |> String.split("</pre>", parts: 2)
      |> List.first()
      |> then(&Regex.scan(~r{<code[^>]*>(\d+)}, &1))
      |> Enum.map(&List.last/1)
    end

    test "every line is numbered, including the ones with no answer" do
      {:ok, live, _html} = live(build_conn(), ~p"/")

      # `@n` counts physical lines, so a gutter that skipped the heading and
      # the blank would be numbering something other than what `@n` means.
      html = render_change(live, :edit, %{"source" => "# heading\n\n19 + 22\nprose\n@3 + 100"})

      assert gutter(html) == ~w(1 2 3 4 5)
      assert html =~ "141"
    end

    test "the numbers a reader would type match what the reference resolves to" do
      {:ok, live, _html} = live(build_conn(), ~p"/")

      # Line 3 is `19 + 22`, so `@3 + 100` must be 141 and the gutter must call
      # that line 3. The two have to agree or the numbers are decoration.
      html = render_change(live, :edit, %{"source" => "# heading\n\n19 + 22\n@3 + 100"})

      assert gutter(html) == ~w(1 2 3 4)
      assert html =~ "141"
    end

    test "an empty sheet still numbers its one line" do
      {:ok, live, _html} = live(build_conn(), ~p"/")

      assert gutter(render_change(live, :edit, %{"source" => ""})) == ~w(1)
    end
  end

  describe "the timeline" do
    test "a set of dates is drawn as well as listed" do
      {:ok, live, _html} = live(build_conn(), ~p"/")

      render_change(live, :edit, %{"source" => "every Monday"})
      html = render_click(live, :select, %{"line" => "0"})

      assert html =~ "<figure"
      # Five evenly spaced Mondays, so five marks at five distinct positions.
      positions = Regex.scan(~r/left: ([\d.]+)%; width:/, html) |> Enum.map(&List.last/1)
      assert length(positions) == 5
      assert length(Enum.uniq(positions)) == 5
    end

    test "an answer with no place in time is drawn no axis" do
      {:ok, live, _html} = live(build_conn(), ~p"/")

      render_change(live, :edit, %{"source" => "19 + 22"})
      html = render_click(live, :select, %{"line" => "0"})

      assert html =~ "41"
      refute html =~ "<figure"
    end

    test "an axis crossing zones says which clock it is in" do
      {:ok, live, _html} = live(build_conn(), ~p"/")

      source = "9am to 5pm London and 9am to 5pm New York"
      render_change(live, :edit, %{"source" => source})
      html = render_click(live, :select, %{"line" => "0"})

      assert html =~ "Times shown in New York"
    end

    test "an ordinary clock span needs no zone caption" do
      {:ok, live, _html} = live(build_conn(), ~p"/")

      render_change(live, :edit, %{"source" => "9am to 5pm"})
      html = render_click(live, :select, %{"line" => "0"})

      assert html =~ "<figure"
      refute html =~ "Times shown in"
    end
  end

  describe "sharing" do
    test "opening a shared link replaces the sheet and its locale" do
      {:ok, live, _html} = live(build_conn(), ~p"/")

      payload = LocalizePad.Share.encode("1.234,5 + 1", :de)
      html = render_click(live, :open_shared, %{"payload" => payload})

      assert html =~ "1.235,5"
      assert html =~ ~s(value="de" selected)
    end

    test "a bad link leaves the sheet alone rather than failing the page" do
      {:ok, live, _html} = live(build_conn(), ~p"/")

      render_change(live, :edit, %{"source" => "19 + 22"})
      html = render_click(live, :open_shared, %{"payload" => "not a real payload"})

      assert html =~ "41"
    end

    test "share produces a payload that decodes back to the sheet" do
      {:ok, live, _html} = live(build_conn(), ~p"/")

      render_change(live, :edit, %{"source" => "19 + 22"})
      render_click(live, :share)

      assert_push_event(live, "share", %{payload: payload})
      assert {:ok, "19 + 22", :en} = LocalizePad.Share.decode(payload)
    end
  end

  describe "keyboard shortcuts" do
    test "escape dismisses the detail panel" do
      {:ok, live, _html} = live(build_conn(), ~p"/")

      render_change(live, :edit, %{"source" => "every Monday"})
      opened = render_click(live, :select, %{"line" => "0"})
      dismissed = render_click(live, :dismiss)

      assert opened =~ "temporal_set"
      refute dismissed =~ "temporal_set"
    end

    test "the download shortcut sends the same file as the button" do
      {:ok, live, _html} = live(build_conn(), ~p"/")

      render_change(live, :edit, %{"source" => "19 + 22"})
      render_click(live, :download)

      assert_push_event(live, "download", %{filename: "localize-pad.md", content: content})
      assert content =~ "19 + 22   // 41"
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
