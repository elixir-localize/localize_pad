defmodule LocalizePadWeb.Router do
  use LocalizePadWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session

    # Locale discovery runs before anything renders, because in this app the
    # locale is not decoration — it decides how a sheet's numbers and dates are
    # *parsed*, not merely how they are displayed. `PutLocale` must follow
    # `fetch_session`, which is what makes the `:session` source readable.
    #
    # Source order is most-explicit-first: a locale the user chose (session),
    # then one they asked for in this request (query), then the browser's
    # preference (accept-language).
    plug Localize.Plug.PutLocale,
      from: [:session, :query, :accept_language],
      gettext: LocalizePadWeb.Gettext

    plug Localize.Plug.PutSession

    # A stable id for this browser session, so the windows a person has open
    # can find each other. Minted here rather than derived from anything
    # existing: the session cookie is signed, so this cannot be forged into
    # somebody else's, and a *missing* id must never collapse into a shared
    # default — that would put strangers on one topic.
    plug :put_session_id

    plug :fetch_live_flash
    plug :put_root_layout, html: {LocalizePadWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  defp put_session_id(conn, _options) do
    case get_session(conn, "session_id") do
      nil -> put_session(conn, "session_id", Base.url_encode64(:crypto.strong_rand_bytes(16)))
      _already_has_one -> conn
    end
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", LocalizePadWeb do
    pipe_through :browser

    live "/", SheetLive
  end

  # Other scopes may use custom stacks.
  # scope "/api", LocalizePadWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:localize_pad, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: LocalizePadWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
