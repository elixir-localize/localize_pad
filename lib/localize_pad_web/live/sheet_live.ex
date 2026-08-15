defmodule LocalizePadWeb.SheetLive do
  @moduledoc """
  The notepad: text on the left, answers in the margin on the right.

  ## Keeping the two columns aligned

  The whole illusion depends on line *n* of the textarea sitting at exactly the
  same height as answer *n* beside it. Both columns therefore share one
  monospace font stack and one line height, and the textarea does not soft-wrap
  — a wrapped line would occupy two rows on the left and one on the right, and
  every answer below it would drift. Long lines scroll horizontally instead.

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

  alias LocalizePad.{Sheet, Value}

  @sample """
  # A first sheet

  Breakfast: 19 + 22
  hotel = 120
  hotel * 3 nights
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
    |> assign(:total, format_total(sheet, socket.assigns.locale))
    |> assign(:detail, detail_for(sheet, socket.assigns[:selected], socket.assigns.locale))
  end

  defp detail_for(_sheet, nil, _locale), do: nil

  defp detail_for(sheet, index, locale) do
    with %{value: value} = line when not is_nil(value) <- Enum.at(sheet.lines, index),
         {:ok, parts} <- Value.detail(value, locale: locale) do
      %{line: line, parts: parts, kind: Value.kind(value)}
    else
      _nothing_to_show -> nil
    end
  end

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
      </header>

      <form phx-change="edit" class="min-h-0 flex-1">
        <div class="flex h-full overflow-hidden rounded-lg border border-base-300">
          <textarea
            name="source"
            phx-debounce="150"
            wrap="off"
            spellcheck="false"
            autocomplete="off"
            aria-label="Sheet"
            class="sheet-text w-3/5 resize-none overflow-auto border-0 bg-transparent p-4 focus:outline-none focus:ring-0"
          >{@source}</textarea>

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
      </section>

      <footer class="mt-3 flex justify-end text-sm">
        <span :if={@total} class="rounded-md bg-base-200 px-3 py-1">
          <span class="opacity-60">Total</span>
          <span class="ml-2 font-semibold">{@total}</span>
        </span>
      </footer>
    </div>
    """
  end
end
