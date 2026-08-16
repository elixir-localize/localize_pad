defmodule LocalizePadWeb.SheetLive do
  @moduledoc """
  The notepad: text on the left, answers in the margin on the right.

  ## Keeping the two columns aligned

  The whole illusion depends on line *n* of the textarea sitting at exactly the
  same height as answer *n* beside it. Both columns therefore share one
  monospace font stack and one line height, and the textarea does not soft-wrap
  — a wrapped line would occupy two rows on the left and one on the right, and
  every answer below it would drift. Long lines scroll horizontally instead.

  ## The editor is two layers

  Syntax highlighting means colouring text, and a `<textarea>` cannot colour
  its own contents. The usual answer is to replace it with a code editor —
  CodeMirror was the plan — but that trades away the one property this layout
  depends on: a textarea's line boxes are what the answer column is aligned
  against, and an editor that renders lines its own way puts that at risk for
  benefits this language does not need.

  So the textarea stays and gains a layer beneath it: the same text, coloured,
  drawn by `LocalizePad.Highlight` from the engine's own tokens. The textarea
  above it keeps its caret and its selection and gives up only its text colour.

  The two layers must agree byte for byte on every metric — font, size, line
  height, padding, wrapping — and on scroll position, which is why the hook
  follows one with the other. A character of disagreement is a character of
  drift, and it compounds along the line.

  ## The gutter numbers every line

  `@3` is the answer on line 3, and without a gutter the only way to find the
  number is to count. So the numbers are there, dim enough to read past.

  They count *every* physical line — blanks, headings, comments — because that
  is what `@n` counts. Numbering only the lines that carry an answer would look
  tidier and would be a lie, and a lie about line numbers is one the reader
  cannot catch: `@3` would quietly resolve to something other than the row
  labelled 3.

  ## The columns scroll as one

  Line *n* of the text, its number and its answer are the same row, so they
  cannot scroll independently without the rows ceasing to mean the same thing.
  Vertical scroll is therefore shared in both directions — dragging the answer
  column moves the text and vice versa — with a flag to stop each update
  triggering the other back.

  Horizontal scroll is the text's alone. A long line running off to the right
  must not take the line numbers or the answers with it.

  The gutter follows the text vertically and stays put horizontally. Scrolling
  a long line to the right must not carry the line numbers off the edge with
  it, which is the one way this differs from the highlight layer beneath the
  textarea.

  ## Recalculation

  Every keystroke re-evaluates the sheet, debounced so a fast typist sends
  round-trips at a readable rate rather than per character. A full re-evaluation
  is deliberate: at notepad scale it costs microseconds, and it means the
  displayed answers can never disagree with the text that produced them.

  ## Locale

  The locale picker is not a display preference. Changing it re-reads the
  sheet, so `1.234,5` becomes a different number and `3 meters` a different
  phrase. That is the product, so it lives in the header rather than in a
  settings page.

  ## Where a sheet lives

  In the browser. The sheet is held in `localStorage` and restored on mount,
  which means a reload does not lose your work and no account is needed to
  start. It also means a sheet is not shared between devices, and that is the
  honest trade for now — the alternative is an account before the first
  calculation.

  The session cookie would have been the smaller change and the wrong one: it
  is capped at about 4 KB, which a working sheet exceeds sooner than anyone
  expects, and it would fail by silently truncating.

  ## Windows of one session move together

  Every browser window is its own LiveView process with its own assigns —
  LiveView synchronises nothing between them by default, and a shared session
  cookie does not change that. So the windows are joined explicitly: each
  subscribes to a PubSub topic derived from a per-session id, and every event
  that changes the document publishes to it.

  The topic comes from a signed session cookie, so it cannot be forged into
  somebody else's, and a request arriving without an id publishes nothing at
  all rather than falling back to a shared topic — that default would have put
  strangers on one channel.

  This does mean the server now *sees* sheet contents in transit, where before
  it never did. It still stores none, and the sharing link is still a fragment
  the server never receives. But the flat claim that a sheet never reaches the
  server is no longer true, and the section below says so where it used to
  claim otherwise.

  Conflicts are resolved last-write-wins, tempered by one rule: a window whose
  textarea has focus ignores incoming changes. The person actually typing is
  the better authority for that moment, and without it the last window to
  render would win an argument with the one being used. Genuine concurrent
  editing of the same line is not solved here and would need a CRDT.

  ## Sharing

  The whole sheet goes into the URL fragment, so a link needs no account and
  leaves no record. A fragment is never sent in an HTTP request, so a shared
  link does not pass through the server's logs — see `LocalizePad.Share`.

  A shared link beats whatever is in `localStorage`: someone who follows a link
  wants the sheet in the link.

  ## Opening a sheet

  The file is read in the browser and arrives as text, so an upload is an
  ordinary edit by the time the server sees it. That is not laziness about
  `allow_upload` — it is the same promise the rest of this makes: the server
  never receives a file, and there is nothing in a temporary directory to
  clean up or leak.

  ## Answers that do not fit

  Some answers are sets. `every Friday the 13th` is five dates, and a margin
  one line high cannot hold them — it shows `5 dates · Nov 13, 2026, …` and
  truncates.

  Clicking an answer opens a panel *below* the sheet rather than expanding the
  row in place. In place would be the obvious choice and the wrong one: the two
  columns are aligned line for line, and growing one row pushes every answer
  beneath it out of step with its text. A panel underneath cannot do that.

  """

  use LocalizePadWeb, :live_view

  alias LocalizePad.{Examples, Highlight, Share, Sheet, Timeline, Value}

  @sample """
  # A first sheet

  Breakfast: 19 + 22
  hotel = 120
  hotel * 3 for the whole stay
  sum

  // Anything after two slashes is ignored
  3 meters to feet
  100 kg * 9.8 m/s^2
  60 mph to km/h

  distance = 42.195 km
  distance to miles
  @3 + 100
  """

  @impl Phoenix.LiveView
  def mount(_params, session, socket) do
    locale = current_locale()
    topic = topic(session)

    # Only once connected: the first, static render has no process to keep a
    # subscription for.
    if connected?(socket) and topic, do: Phoenix.PubSub.subscribe(LocalizePad.PubSub, topic)

    {:ok,
     socket
     |> assign(:topic, topic)
     |> assign(:locale, locale)
     |> assign(:source, @sample)
     |> assign(:locale_options, locale_options())
     |> assign(:examples, Examples.all())
     |> assign(:selected, nil)
     |> recalculate()}
  end

  @impl Phoenix.LiveView
  def handle_event("edit", %{"source" => source}, socket) do
    {:noreply, socket |> assign(:source, source) |> recalculate() |> publish()}
  end

  # Sent by the storage hook on mount when the browser has a sheet saved.
  def handle_event("restore", %{"source" => source}, socket) when is_binary(source) do
    {:noreply,
     socket |> assign(:source, source) |> assign(:selected, nil) |> recalculate() |> publish()}
  end

  # A link the browser has just been opened with. It wins over stored state.
  def handle_event("open_shared", %{"payload" => payload}, socket) do
    case Share.decode(payload) do
      {:ok, source, locale} ->
        Localize.put_locale(locale)

        {:noreply,
         socket
         |> assign(:source, source)
         |> assign(:locale, locale)
         |> assign(:selected, nil)
         |> recalculate()
         |> publish()}

      # A link may be truncated by a chat client or simply made up. Leaving the
      # sheet as it was beats failing the page.
      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("dismiss", _params, socket) do
    {:noreply, socket |> assign(:selected, nil) |> assign(:detail, nil)}
  end

  # The hook reads the file in the browser and sends its text, so an upload is
  # an ordinary edit by the time it arrives — no upload plumbing, and the
  # server still never receives a file. `from_markdown/1` undoes the answer
  # column the exporter writes; see `LocalizePad.Sheet`.
  def handle_event("open", %{"content" => content}, socket) when is_binary(content) do
    case Sheet.from_markdown(content) do
      {:ok, source, locale} ->
        # A file that names its locale carries it, for the same reason a shared
        # link does: `1.234,5` is a different number in `de`, so opening a
        # German sheet under an English locale would change its answers.
        locale = locale || socket.assigns.locale
        Localize.put_locale(locale)

        {:noreply,
         socket
         |> assign(:source, source)
         |> assign(:locale, locale)
         |> assign(:selected, nil)
         |> recalculate()
         |> publish()}

      # Somebody opened a photograph. Leaving the sheet alone beats clearing it.
      {:error, :empty} ->
        {:noreply, socket}
    end
  end

  def handle_event("example", %{"id" => id}, socket) do
    case Examples.fetch(id) do
      {:ok, example} ->
        locale = example.locale || socket.assigns.locale
        Localize.put_locale(locale)

        {:noreply,
         socket
         |> assign(:source, example.source)
         |> assign(:locale, locale)
         |> assign(:selected, nil)
         |> recalculate()
         |> publish()}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("download", _params, socket) do
    markdown = Sheet.to_markdown(socket.assigns.sheet)

    {:noreply, push_event(socket, "download", %{filename: "localize-pad.md", content: markdown})}
  end

  def handle_event("select", %{"line" => line}, socket) do
    index = String.to_integer(line)

    # Clicking the open line closes it, so the panel is dismissable without a
    # separate control.
    selected = if socket.assigns.selected == index, do: nil, else: index

    {:noreply,
     socket
     |> assign(:selected, selected)
     |> assign(:detail, detail_for(socket.assigns.sheet, selected, socket.assigns.locale))}
  end

  def handle_event("set_locale", %{"locale" => locale}, socket) do
    case Localize.validate_locale(locale) do
      {:ok, language_tag} ->
        Localize.put_locale(language_tag)

        {:noreply,
         socket
         |> assign(:locale, language_tag.cldr_locale_id)
         |> recalculate()
         |> publish()}

      # An unknown locale simply leaves the sheet as it was. Nothing the picker
      # can send should be able to break a document.
      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  @impl Phoenix.LiveView
  def handle_info({:sheet, from, source, locale}, socket) when from != self() do
    # Another window of this session changed the sheet. The locale travels with
    # it because it decides what the numbers *mean* — mirroring the text while
    # leaving the locale behind would show the other window different answers.
    Localize.put_locale(locale)

    {:noreply,
     socket
     |> assign(:source, source)
     |> assign(:locale, locale)
     |> assign(:selected, nil)
     |> recalculate()
     |> push_event("remote", %{source: source})}
  end

  # Our own broadcast coming back. PubSub has no exclude-self, so the guard
  # above does it, and this clause keeps the unmatched message from crashing
  # the view.
  def handle_info({:sheet, _from, _source, _locale}, socket), do: {:noreply, socket}

  # The other windows of this session, and nobody else's. A session with no id
  # publishes nothing rather than falling back to a shared topic.
  defp topic(session) do
    case session do
      %{"session_id" => id} when is_binary(id) -> "sheet:" <> id
      _no_session -> nil
    end
  end

  defp publish(%{assigns: %{topic: nil}} = socket), do: socket

  defp publish(socket) do
    Phoenix.PubSub.broadcast(
      LocalizePad.PubSub,
      socket.assigns.topic,
      {:sheet, self(), socket.assigns.source, socket.assigns.locale}
    )

    socket
  end

  defp recalculate(socket) do
    sheet = Sheet.new(socket.assigns.source, locale: socket.assigns.locale)

    socket
    |> assign(:sheet, sheet)
    |> assign(:highlighted, Highlight.lines(socket.assigns.source, locale: socket.assigns.locale))
    |> assign(:share_payload, Share.encode(socket.assigns.source, socket.assigns.locale))
    |> assign(:total, format_total(sheet, socket.assigns.locale))
    |> assign(:detail, detail_for(sheet, socket.assigns[:selected], socket.assigns.locale))
  end

  defp detail_for(_sheet, nil, _locale), do: nil

  defp detail_for(sheet, index, locale) do
    with %{value: value} = line when not is_nil(value) <- Enum.at(sheet.lines, index),
         {:ok, parts} <- Value.detail(value, locale: locale) do
      %{
        line: line,
        parts: parts,
        kind: Value.kind(value),
        timeline: timeline_for(value, locale)
      }
    else
      _nothing_to_show -> nil
    end
  end

  # Most answers have no position in time, so most panels have no timeline.
  defp timeline_for(value, locale) do
    case Timeline.build(value, locale: locale) do
      {:ok, timeline} -> timeline
      :error -> nil
    end
  end

  # A point in time has no width to draw, and a run of them would vanish
  # entirely. The floor is the smallest mark that still reads as a mark.
  defp percent(fraction) do
    fraction |> max(0.0) |> min(1.0) |> Kernel.*(100) |> Float.round(3)
  end

  defp mark_width(fraction) do
    fraction |> percent() |> max(0.8)
  end

  # Which clock the axis is drawn against, but only when it could be a
  # surprise. A day-scale axis has no clock worth naming, and UTC is what an
  # unzoned sheet already assumes — saying so would be noise on almost every
  # timeline in order to be useful on the few that cross zones.
  defp zone_label(%{unit: :hour, zone: zone}) when zone != "Etc/UTC" do
    zone |> String.split("/") |> List.last() |> String.replace("_", " ")
  end

  defp zone_label(_timeline), do: nil

  # Tick labels are centred on their tick, which puts half of the first one
  # off the left edge and half of the last off the right. The two at the ends
  # hang inward instead.
  defp tick_alignment(at) when at < 0.05, do: "translate-x-0"
  defp tick_alignment(at) when at > 0.95, do: "-translate-x-full"
  defp tick_alignment(_at), do: "-translate-x-1/2"

  defp format_total(sheet, locale) do
    case Sheet.total(sheet) do
      nil ->
        nil

      total ->
        case Value.format(total, locale: locale) do
          {:ok, formatted} -> formatted
          {:error, _reason} -> nil
        end
    end
  end

  defp current_locale do
    Localize.get_locale().cldr_locale_id
  end

  # Each locale is named in its own language — "Deutsch", not "German". A
  # picker is read by the person who wants that locale, and they should be able
  # to find it without first knowing what English calls it.
  #
  # `supported_locales/0` always returns a list: with `:supported_locales`
  # unset it falls back to every locale CLDR knows, which would put ~766
  # entries in this select. The configured list in `config/config.exs` is what
  # keeps it to five.
  defp locale_options do
    Enum.map(Localize.supported_locales(), fn locale ->
      case Localize.Language.display_name(to_string(locale), locale: locale) do
        {:ok, name} -> {String.capitalize(name), to_string(locale)}
        {:error, _reason} -> {to_string(locale), to_string(locale)}
      end
    end)
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="mx-auto flex h-screen max-w-5xl flex-col px-4 py-6">
      <header class="mb-4 flex items-baseline justify-between gap-4">
        <h1 class="text-lg font-semibold tracking-tight">LocalizePad</h1>

        <div class="flex items-center gap-3">
          <%!-- No `phx-click`. Copying to the clipboard requires transient
          user activation, and a server round trip outlives it — the write is
          silently refused, which is exactly how this failed. The payload is
          rendered with the sheet so the click has everything it needs and can
          copy synchronously. --%>
          <button
            id="share"
            type="button"
            data-payload={@share_payload}
            class="btn btn-sm btn-ghost"
            title="Copy a link to this sheet"
          >
            <%!-- The label is the hook's, not the server's. `data-payload`
            changes with every keystroke, so LiveView patches this button
            often — and a patch mid-confirmation would wipe "Copied" a moment
            after it appeared, which looks exactly like a button that did
            nothing. --%>
            <span
              id="share-label"
              phx-update="ignore"
            >
              Share
            </span>
          </button>

          <div class="dropdown dropdown-end">
            <div tabindex="0" role="button" class="btn btn-sm btn-ghost" title="Open an example sheet">
              Examples
            </div>
            <ul
              tabindex="0"
              class="dropdown-content menu z-10 w-64 rounded-box bg-base-200 p-2 shadow"
            >
              <li :for={example <- @examples}>
                <button type="button" phx-click="example" phx-value-id={example.id}>
                  <span class="truncate">{example.title}</span>
                  <span class="ml-auto shrink-0 opacity-40">{example.locale}</span>
                </button>
              </li>
            </ul>
          </div>

          <label
            class="btn btn-sm btn-ghost cursor-pointer"
            title="Open a sheet you downloaded earlier (⌘O)"
          >
            Open
            <input id="open-sheet" type="file" accept=".md,.markdown,.txt,text/plain" class="hidden" />
          </label>

          <button
            type="button"
            phx-click="download"
            class="btn btn-sm btn-ghost"
            title="Download this sheet as Markdown (⌘S)"
          >
            Download
          </button>

          <form phx-change="set_locale">
            <label class="flex items-center gap-2 text-sm">
              <span class="opacity-60">Locale</span>
              <select
                name="locale"
                class="select select-sm select-bordered"
                aria-label="Sheet locale"
              >
                <option
                  :for={{name, code} <- @locale_options}
                  value={code}
                  selected={code == to_string(@locale)}
                >
                  {name}
                </option>
              </select>
            </label>
          </form>
        </div>
      </header>

      <form id="sheet" phx-hook=".SheetStorage" phx-change="edit" class="min-h-0 flex-1">
        <div class="flex h-full overflow-hidden rounded-lg border border-base-300">
          <div class="sheet-editor flex-1">
            <pre id="gutter" class="sheet-text sheet-gutter" aria-hidden="true"><code
              :for={number <- 1..length(@highlighted)//1}
            >{number}{"\n"}</code></pre>

            <div class="sheet-layers">
              <pre id="highlight" class="sheet-text sheet-highlight" aria-hidden="true"><code
                :for={segments <- @highlighted}
              ><span
                  :for={{class, text} <- segments}
                  class={class && "tok-#{class}"}
                >{text}</span>{"\n"}</code></pre>

              <textarea
                name="source"
                phx-debounce="150"
                wrap="off"
                spellcheck="false"
                autocomplete="off"
                aria-label="Sheet"
                class="sheet-text sheet-input resize-none border-0 bg-transparent focus:outline-none focus:ring-0"
              >{@source}</textarea>
            </div>
          </div>

          <%!-- Fixed rather than sized to content: an adaptive column would
          resize on every keystroke and drag the divider with it. 30% fits the
          ordinary run of answers — a converted unit, a formatted amount — and
          a set of dates truncates, which it did at any width and is what the
          detail panel below the sheet is for. --%>
          <div
            id="answers"
            class="sheet-answers w-[30%] shrink-0 overflow-auto border-l border-base-300 bg-base-200/40 p-4 text-right"
          >
            <div
              :for={line <- @sheet.lines}
              phx-click={line.formatted && "select"}
              phx-value-line={line.index}
              class={[
                "truncate",
                line.formatted && "cursor-pointer hover:opacity-70",
                line.index == @selected && "font-semibold",
                line.error && "opacity-40",
                line.kind in [:heading, :comment] && "opacity-30"
              ]}
              title={line.error && inspect(line.error)}
            >
              {line.formatted || raw("&nbsp;")}
            </div>
          </div>
        </div>
      </form>

      <section
        :if={@detail}
        class="mt-3 rounded-lg border border-base-300 bg-base-200/40 px-4 py-3 text-sm"
      >
        <div class="mb-2 flex items-baseline justify-between gap-4">
          <code class="sheet-text truncate opacity-60">{@detail.line.source}</code>
          <span class="shrink-0 opacity-40">{@detail.kind}</span>
        </div>

        <ol class="sheet-text flex flex-wrap gap-x-6 gap-y-1">
          <li :for={part <- @detail.parts}>{part}</li>
        </ol>

        <figure :if={@detail.timeline} class="mt-4">
          <figcaption :if={zone_label(@detail.timeline)} class="mb-1 text-xs opacity-50">
            Times shown in {zone_label(@detail.timeline)}
          </figcaption>

          <div class="relative h-8 rounded border border-base-300 bg-base-100">
            <div
              :for={tick <- @detail.timeline.ticks}
              class="absolute top-0 h-full border-l border-base-300/70"
              style={"left: #{percent(tick.at)}%"}
              aria-hidden="true"
            >
            </div>
            <div
              :for={mark <- @detail.timeline.marks}
              class="absolute top-1 h-6 rounded-sm bg-primary/70"
              style={"left: #{percent(mark.start)}%; width: #{mark_width(mark.width)}%"}
              title={mark.label}
            >
            </div>
          </div>

          <figcaption class="relative mt-1 h-4 text-xs opacity-50">
            <span
              :for={tick <- @detail.timeline.ticks}
              class={["absolute whitespace-nowrap", tick_alignment(tick.at)]}
              style={"left: #{percent(tick.at)}%"}
            >
              {tick.label}
            </span>
          </figcaption>
        </figure>
      </section>

      <footer class="mt-3 flex justify-end text-sm">
        <span :if={@total} class="rounded-md bg-base-200 px-3 py-1">
          <span class="opacity-60">Total</span>
          <span class="ml-2 font-semibold">{@total}</span>
        </span>
      </footer>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".SheetStorage">
      const KEY = "localize_pad.sheet"
      const FRAGMENT = "#s="

      export default {
        mounted() {
          const textarea = this.el.querySelector("textarea[name=source]")

          this.restore(textarea)
          this.persist(textarea)
          this.shortcuts(textarea)
          this.syncScroll(textarea)
          this.openFile()

          // A sibling window changed the sheet.
          this.handleEvent("remote", ({source}) => {
            // Not while this window is the one being typed in. Overwriting a
            // focused textarea would take the caret and lose the half-finished
            // line — and the person typing is the better authority for the
            // moment. This is last-write-wins, and the focus check is what
            // keeps that from meaning "last window to render wins".
            if (document.activeElement === textarea) return
            if (textarea.value === source) return

            textarea.value = source
            window.localStorage.setItem(KEY, source)
          })

          this.handleEvent("download", ({filename, content}) => {
            this.save(filename, content, "text/markdown")
          })

          const button = document.getElementById("share")

          button &&
            button.addEventListener("click", async () => {
              const url =
                window.location.origin +
                window.location.pathname +
                FRAGMENT +
                button.dataset.payload

              // The address bar gets it either way, so there is always a link
              // to copy by hand if the clipboard refuses.
              window.history.replaceState(null, "", url)

              // Confirm first, correct afterwards. `writeText` returns a
              // promise that in some browsers neither resolves nor rejects
              // promptly, and feedback that waits on it can simply never
              // arrive — which looks identical to a button that does nothing,
              // and is what this button was already accused of.
              const label = document.getElementById("share-label")
              this.flash(label, "Copied")

              try {
                await navigator.clipboard.writeText(url)
              } catch (_refused) {
                // Denied permission, or an insecure context. The link is in
                // the address bar either way, so say that rather than leave a
                // false confirmation standing.
                this.flash(label, "In address bar")
              }
            })
        },

        // A link beats stored state: someone who follows a link wants the
        // sheet in the link.
        restore(textarea) {
          const hash = window.location.hash

          if (hash.startsWith(FRAGMENT)) {
            this.pushEvent("open_shared", {payload: hash.slice(FRAGMENT.length)})
            return
          }

          const saved = window.localStorage.getItem(KEY)

          // Only replace the server's sample when there is something to
          // replace it with. A first visit should see a sheet, not a blank.
          if (saved !== null && saved !== textarea.value) {
            textarea.value = saved
            this.pushEvent("restore", {source: saved})
          }
        },

        // Reading the file here rather than uploading it keeps the promise the
        // rest of the app makes: a sheet reaches the server as text the user
        // could have typed, and never as a file sitting in a temporary
        // directory somewhere.
        openFile() {
          // Queried from the document, not from `this.el`: the hook is on the
          // form and the control lives in the header beside Share and
          // Download, where it belongs for the reader.
          const input = document.getElementById("open-sheet")
          if (!input) return

          input.addEventListener("change", async () => {
            const file = input.files && input.files[0]
            if (!file) return

            this.pushEvent("open", {content: await file.text()})
            // Clearing it means the same file can be opened twice running;
            // without this the second change event never fires.
            input.value = ""
          })
        },

        // The coloured layer is a separate scroll box from the textarea over
        // it, so it has to be told where the textarea got to. Without this a
        // long line scrolls the text the user is editing away from its own
        // colours.
        syncScroll(textarea) {
          const highlight = this.el.querySelector("#highlight")
          const gutter = this.el.querySelector("#gutter")
          const answers = this.el.querySelector("#answers")
          if (!highlight) return

          // The four columns are one document: line n of the text, its number
          // and its answer are the same row. Scrolling any of them has to move
          // the others or the rows stop meaning the same thing.
          //
          // The flag is what keeps that from becoming a loop — setting
          // scrollTop fires `scroll`, which would set it back.
          let syncing = false

          const share = (top, left) => {
            if (syncing) return
            syncing = true

            highlight.scrollTop = top
            if (gutter) gutter.scrollTop = top
            if (answers) answers.scrollTop = top

            // Horizontal is the text's alone. A long line scrolling right must
            // not drag the line numbers or the answers off the edge with it.
            if (left !== null) {
              highlight.scrollLeft = left
              textarea.scrollLeft = left
            }

            if (textarea.scrollTop !== top) textarea.scrollTop = top
            syncing = false
          }

          textarea.addEventListener("scroll", () =>
            share(textarea.scrollTop, textarea.scrollLeft)
          )
          textarea.addEventListener("input", () =>
            share(textarea.scrollTop, textarea.scrollLeft)
          )
          if (answers) {
            answers.addEventListener("scroll", () => share(answers.scrollTop, null))
          }

          this.handleEvent("scroll-sync", () => share(textarea.scrollTop, textarea.scrollLeft))
          share(textarea.scrollTop, textarea.scrollLeft)
        },

        // A silent copy is indistinguishable from a broken button.
        flash(element, message) {
          element.__original = element.__original || element.textContent.trim()
          element.textContent = message

          clearTimeout(element.__restore)
          element.__restore = setTimeout(() => {
            element.textContent = element.__original
          }, 1400)
        },

        // Save on input rather than on the debounced change, so a reload
        // immediately after typing does not lose the last keystrokes.
        persist(textarea) {
          this.el.addEventListener("input", () => {
            window.localStorage.setItem(KEY, textarea.value)
          })
        },

        shortcuts(textarea) {
          textarea.addEventListener("keydown", (event) => {
            const meta = event.metaKey || event.ctrlKey

            if (meta && event.key === "s") {
              event.preventDefault()
              this.pushEvent("download", {})
            } else if (meta && event.key === "\\") {
              event.preventDefault()
              this.insertReference(textarea)
            } else if (meta && event.key === "o") {
              event.preventDefault()
              document.getElementById("open-sheet")?.click()
            } else if (event.key === "Escape") {
              this.pushEvent("dismiss", {})
            }
          })
        },

        // ⌘\ inserts a reference to the line above the cursor, which is the
        // one people mean when they reach for it.
        insertReference(textarea) {
          const before = textarea.value.slice(0, textarea.selectionStart)
          const line = before.split("\n").length

          if (line < 2) return

          const reference = "@" + (line - 1)
          const after = textarea.value.slice(textarea.selectionEnd)

          textarea.value = before + reference + after
          textarea.selectionStart = textarea.selectionEnd = before.length + reference.length
          textarea.dispatchEvent(new Event("input", {bubbles: true}))
        },

        save(filename, content, type) {
          const url = URL.createObjectURL(new Blob([content], {type}))
          const link = document.createElement("a")

          link.href = url
          link.download = filename
          document.body.appendChild(link)
          link.click()
          link.remove()
          URL.revokeObjectURL(url)
        }
      }
    </script>
    """
  end
end
