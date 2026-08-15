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

    plug :fetch_live_flash
    plug :put_root_layout, html: {LocalizePadWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
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
