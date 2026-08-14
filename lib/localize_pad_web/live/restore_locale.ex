defmodule LocalizePadWeb.RestoreLocale do
  @moduledoc """
  An `on_mount` hook that restores the request's locale into the LiveView
  process.

  `Localize.Plug.PutLocale` sets the locale on the connection process during
  the HTTP request, and `Localize.Plug.PutSession` writes it into the session.
  A LiveView runs in its own process, so without this hook the locale set
  during the initial request is lost the moment the socket connects — and a
  sheet would silently change how it parses numbers and dates between the
  first render and the live one.

  Wired into every LiveView by `LocalizePadWeb.live_view/0`.

  """

  @doc """
  Restores the locale recorded in the session by `Localize.Plug.PutSession`.

  ### Arguments

  * `name` - the `on_mount` hook name. Only `:default` is supported.

  * `params` - the LiveView mount params. Unused.

  * `session` - the session map, read for the persisted locale.

  * `socket` - the LiveView socket.

  ### Returns

  * `{:cont, socket}` always. A session carrying no locale, or an unknown
    one, leaves the process on the application default rather than failing
    the mount — a bad locale must never take down a page.

  """
  def on_mount(:default, _params, session, socket) do
    case Localize.Plug.put_locale_from_session(session, gettext: LocalizePadWeb.Gettext) do
      {:ok, _locale} -> {:cont, socket}
      {:error, _reason} -> {:cont, socket}
    end
  end
end
