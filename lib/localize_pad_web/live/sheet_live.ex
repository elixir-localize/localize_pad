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

  ## Sharing

  The whole sheet goes into the URL fragment, so a link needs no account and
  leaves no record. A fragment is never sent to the server, which means the
  hook has to read it and hand it over — see `LocalizePad.Share`.

  A shared link beats whatever is in `localStorage`: someone who follows a link
  wants the sheet in the link.

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

  alias LocalizePad.{Highlight, Share, Sheet, Timeline, Value}

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
  def mount(_params, _session, socket) do
    locale = current_locale()

    {:ok,
     socket
     |> assign(:locale, locale)
     |> assign(:source, @sample)
     |> assign(:locale_options, locale_options())
     |> assign(:selected, nil)
     |> recalculate()}
  end

  @impl Phoenix.LiveView
  def handle_event("edit", %{"source" => source}, socket) do
    {:noreply, socket |> assign(:source, source) |> recalculate()}
  end

  # Sent by the storage hook on mount when the browser has a sheet saved.
  def handle_event("restore", %{"source" => source}, socket) when is_binary(source) do
    {:noreply, socket |> assign(:source, source) |> assign(:selected, nil) |> recalculate()}
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
         |> recalculate()}

      # A link may be truncated by a chat client or simply made up. Leaving the
      # sheet as it was beats failing the page.
      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("share", _params, socket) do
    payload = Share.encode(socket.assigns.source, socket.assigns.locale)

    {:noreply, push_event(socket, "share", %{payload: payload})}
  end

  def handle_event("dismiss", _params, socket) do
    {:noreply, socket |> assign(:selected, nil) |> assign(:detail, nil)}
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
         |> recalculate()}

      # An unknown locale simply leaves the sheet as it was. Nothing the picker
      # can send should be able to break a document.
      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  defp recalculate(socket) do
    sheet = Sheet.new(socket.assigns.source, locale: socket.assigns.locale)

    socket
    |> assign(:sheet, sheet)
    |> assign(:highlighted, Highlight.lines(socket.assigns.source, locale: socket.assigns.locale))
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
          <button
            type="button"
            phx-click="share"
            class="btn btn-sm btn-ghost"
            title="Copy a link to this sheet"
          >
            Share
          </button>

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
          <div class="sheet-editor w-3/5">
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

          <div class="sheet-answers w-2/5 overflow-auto border-l border-base-300 bg-base-200/40 p-4 text-right">
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

          this.handleEvent("download", ({filename, content}) => {
            this.save(filename, content, "text/markdown")
          })

          this.handleEvent("share", ({payload}) => {
            const url = window.location.origin + window.location.pathname + FRAGMENT + payload

            window.history.replaceState(null, "", url)
            navigator.clipboard && navigator.clipboard.writeText(url)
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

        // The coloured layer is a separate scroll box from the textarea over
        // it, so it has to be told where the textarea got to. Without this a
        // long line scrolls the text the user is editing away from its own
        // colours.
        syncScroll(textarea) {
          const highlight = this.el.querySelector("#highlight")
          const gutter = this.el.querySelector("#gutter")
          if (!highlight) return

          const follow = () => {
            highlight.scrollTop = textarea.scrollTop
            highlight.scrollLeft = textarea.scrollLeft
            // The gutter follows vertically only. Scrolling a long line right
            // must not carry the line numbers off the edge with it.
            if (gutter) gutter.scrollTop = textarea.scrollTop
          }

          textarea.addEventListener("scroll", follow)
          textarea.addEventListener("input", follow)
          this.handleEvent("scroll-sync", follow)
          follow()
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
