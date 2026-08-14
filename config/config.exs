# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :localize_pad,
  ecto_repos: [LocalizePad.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :localize_pad, LocalizePadWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: LocalizePadWeb.ErrorHTML, json: LocalizePadWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: LocalizePad.PubSub,
  live_view: [signing_salt: "S2sWiIuL"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :localize_pad, LocalizePad.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  localize_pad: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  localize_pad: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Localize supplies every locale-aware operation in the app: number and unit
# formatting, locale-aware number parsing, the CLDR data behind Calendrical's
# date parser, and the MF2 Gettext interpolator.
#
# `:otp_app` anchors the downloaded locale cache under this app's `priv/`, which
# resolves correctly in mix tasks, `mix test` and releases alike — see the
# Localize README on why a bare relative `:locale_cache_dir` is refused.
#
# `:supported_locales` is the set the sheet's locale picker offers. `:en` is the
# starting point; `:de`, `:fr`, `:es` and `:ja` are the M6 proof locales.
config :localize,
  otp_app: :localize_pad,
  default_locale: :en,
  supported_locales: [:en, :de, :fr, :es, :ja]

# Currency conversion arrives in M4. Until then there is no exchange-rate
# retriever in the supervision tree, so tell Money not to start one implicitly —
# the implicit start is deprecated and would otherwise warn on every boot.
config :ex_money, auto_start_exchange_rate_service: false

# Calendrical resolves IANA zone names ("Asia/Tokyo") through whichever
# timezone database the host application installs. Without this, every
# zone-bearing calculation falls back to UTC.
config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
