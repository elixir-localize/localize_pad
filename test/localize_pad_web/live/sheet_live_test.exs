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

    test "shows a running total when the sheet has one", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/")

      html = render_change(live, :edit, %{"source" => "19\n22"})

      assert html =~ "Total"
      assert html =~ "41"
    end

    test "and no total at all when the sheet mixes kinds", %{conn: conn} do
      # The sample sheet adds numbers, a distance, a force and a speed. There
      # is no total of those, and the footer says nothing rather than picking
      # one line's unit and discarding the rest under a label saying `Total`.
      {:ok, _live, html} = live(conn, ~p"/")

      refute html =~ "Total"
    end

    # `Localize.Plug.PutLocale` honours the query string and `Accept-Language`,
    # and neither is limited to locales this application ships data for. A tag
    # with nothing behind it must not become the sheet's locale: the reader
    # would be told the sheet was Italian and shown English answers.
    test "a browser locale we have no data for opens an English sheet, and says so" do
      conn = get(build_conn(), ~p"/?locale=it")
      {:ok, _live, html} = live(conn)

      assert html =~ ~s(value="en")
      refute html =~ ~s(value="it")
    end

    test "the same for a language tag arriving in a header" do
      conn =
        build_conn()
        |> put_req_header("accept-language", "it-IT,it;q=0.9")
        |> get(~p"/")

      {:ok, _live, html} = live(conn)

      assert html =~ ~s(value="en")
      refute html =~ ~s(value="it-IT")
    end

    test "but a locale we do ship is honoured" do
      conn = get(build_conn(), ~p"/?locale=en-AU")
      {:ok, _live, html} = live(conn)

      assert html =~ ~s(value="en-AU")
      assert html =~ "kilometres"
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

  describe "windows of one session" do
    # Two windows of a session mirror each other. The property that matters
    # more than the feature is that *only* they do: the topic is derived from a
    # signed session cookie, and a session without one publishes nothing rather
    # than falling back to a shared default.
    defp session_topic(conn) do
      "sheet:" <> Plug.Conn.get_session(conn, "session_id")
    end

    # A broadcast stands in for another window, and a window publishes the
    # resolved tag it is holding — not a name for one.
    defp tag(locale) do
      {:ok, language_tag} = LocalizePad.Locales.resolve(locale)

      language_tag
    end

    test "an edit in one window reaches the other" do
      conn = get(build_conn(), ~p"/")
      {:ok, live, _html} = live(conn)

      Phoenix.PubSub.broadcast(
        LocalizePad.PubSub,
        session_topic(conn),
        {:sheet, self(), "19 + 22", tag("en")}
      )

      assert render(live) =~ "41"
    end

    test "the locale travels with the text" do
      # `1.234,5` is a different number in `de`. Mirroring the text without the
      # locale would show the other window different answers from the one that
      # sent it, which is worse than not syncing at all.
      conn = get(build_conn(), ~p"/")
      {:ok, live, _html} = live(conn)

      Phoenix.PubSub.broadcast(
        LocalizePad.PubSub,
        session_topic(conn),
        {:sheet, self(), "1.234,5 + 1", tag("de")}
      )

      html = render(live)
      assert html =~ "1.235,5"
      assert html =~ ~s(value="de")
    end

    test "another session's edit is not received" do
      conn = get(build_conn(), ~p"/")
      {:ok, live, _html} = live(conn)

      render_change(live, :edit, %{"source" => "19 + 22"})

      Phoenix.PubSub.broadcast(
        LocalizePad.PubSub,
        "sheet:somebody-else-entirely",
        {:sheet, self(), "99 + 1", tag("en")}
      )

      html = render(live)
      assert html =~ "41"
      refute html =~ "100"
    end

    test "two sessions get different topics" do
      first = get(build_conn(), ~p"/")
      second = get(build_conn(), ~p"/")

      assert session_topic(first) != session_topic(second)
    end

    test "a session id survives across requests" do
      conn = get(build_conn(), ~p"/")
      again = conn |> recycle() |> get(~p"/")

      assert session_topic(conn) == session_topic(again)
    end

    test "editing broadcasts, and does not echo back to the sender" do
      conn = get(build_conn(), ~p"/")
      {:ok, live, _html} = live(conn)

      Phoenix.PubSub.subscribe(LocalizePad.PubSub, session_topic(conn))
      render_change(live, :edit, %{"source" => "19 + 22"})

      assert_receive {:sheet, from, "19 + 22", %{language: :en}}
      refute from == self()
    end
  end

  describe "the examples" do
    test "they are offered by name" do
      {:ok, _live, html} = live(build_conn(), ~p"/")

      assert html =~ "Questions about time"
      assert html =~ "Ein deutsches Blatt"
    end

    test "choosing one loads it and its locale together" do
      {:ok, live, _html} = live(build_conn(), ~p"/")

      html = render_click(live, :example, %{"id" => "05-ein-deutsches-blatt"})

      # The German pad read in English would answer differently, so the locale
      # travels with it.
      assert html =~ ~s(value="de")
      assert html =~ "1.235,5"
      assert html =~ "5 Termine"
    end

    test "an id that names no example leaves the sheet alone" do
      {:ok, live, _html} = live(build_conn(), ~p"/")

      render_change(live, :edit, %{"source" => "19 + 22"})
      html = render_click(live, :example, %{"id" => "../../etc/passwd"})

      assert html =~ "41"
    end
  end

  describe "opening a sheet" do
    test "a downloaded sheet opens back to what it was" do
      {:ok, live, _html} = live(build_conn(), ~p"/")

      original = "# Trip\n\nBreakfast: 19 + 22\nhotel = 120\nhotel * 3"
      markdown = original |> LocalizePad.Sheet.new(locale: :en) |> LocalizePad.Sheet.to_markdown()

      html = render_click(live, :open, %{"content" => markdown})

      assert html =~ "41"
      assert html =~ "360"
      # The answer column the exporter wrote must not come back as text, or a
      # second download would carry it twice.
      refute html =~ "// 41"
    end

    test "a file that names its locale is read in it" do
      {:ok, live, _html} = live(build_conn(), ~p"/")

      markdown =
        "1.234,5 + 1" |> LocalizePad.Sheet.new(locale: :de) |> LocalizePad.Sheet.to_markdown()

      html = render_click(live, :open, %{"content" => markdown})

      assert html =~ "1.235,5"
      assert html =~ ~s(value="de")
    end

    test "a plain list of sums is a sheet" do
      {:ok, live, _html} = live(build_conn(), ~p"/")

      html = render_click(live, :open, %{"content" => "19 + 22\n3 meters to feet"})

      assert html =~ "41"
      assert html =~ "9.84252 feet"
    end

    test "an unreadable file leaves the sheet alone" do
      {:ok, live, _html} = live(build_conn(), ~p"/")

      render_change(live, :edit, %{"source" => "19 + 22"})
      html = render_click(live, :open, %{"content" => "   "})

      assert html =~ "41"
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
      assert html =~ ~s(value="de")
    end

    test "a bad link leaves the sheet alone rather than failing the page" do
      {:ok, live, _html} = live(build_conn(), ~p"/")

      render_change(live, :edit, %{"source" => "19 + 22"})
      html = render_click(live, :open_shared, %{"payload" => "not a real payload"})

      assert html =~ "41"
    end

    test "the share payload is rendered with the sheet, ready for the click" do
      # It is in the markup rather than fetched on click, because copying to
      # the clipboard needs the user's gesture still to be live and a server
      # round trip outlives it.
      {:ok, live, _html} = live(build_conn(), ~p"/")

      html = render_change(live, :edit, %{"source" => "19 + 22"})

      assert [_whole, payload] = Regex.run(~r/id="share"[^>]*data-payload="([^"]+)"/, html)
      assert {:ok, "19 + 22", locale} = LocalizePad.Share.decode(payload)
      assert to_string(locale) == "en"
    end

    test "the payload follows the sheet as it changes" do
      {:ok, live, _html} = live(build_conn(), ~p"/")

      payload_in = fn html ->
        [_whole, payload] = Regex.run(~r/id="share"[^>]*data-payload="([^"]+)"/, html)
        payload
      end

      first = payload_in.(render_change(live, :edit, %{"source" => "19 + 22"}))
      second = payload_in.(render_change(live, :edit, %{"source" => "19 + 23"}))

      assert {:ok, "19 + 22", _first_locale} = LocalizePad.Share.decode(first)
      assert {:ok, "19 + 23", _second_locale} = LocalizePad.Share.decode(second)
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

  # TEMPORARY, for a demo. Delete with the feature.
  describe "hiding the locale control" do
    test "takes the label and the field away, and gives them back", %{conn: conn} do
      {:ok, live, html} = live(conn, ~p"/")

      assert html =~ "Sheet locale, as a language tag"

      hidden = render_click(live, :toggle_locale_control, %{})

      refute hidden =~ "Sheet locale, as a language tag"
      refute hidden =~ ">Locale<"

      assert render_click(live, :toggle_locale_control, %{}) =~ "Sheet locale, as a language tag"
    end
  end
end
