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
# `:domain` so that Localize's own log lines stay attributable. It tags them
# `[:localize]`, and a runtime locale download that fails logs there — without
# the key the tag is dropped and the line reads as an unattributed error.
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :domain]

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
# `:supported_locales` is the set whose CLDR data is downloaded. `:en` is the
# starting point; `:de`, `:fr`, `:es` and `:ja` are the M6 proof locales.
#
# `en-AU` and `en-GB` are here because a territory only changes an answer if its
# data was fetched. Without them CLDR resolves both to `en` and hands back US
# conventions — `3/4/2026` reads as March 4 rather than 3 April, and formats
# come back as `4/3/26`. That is a wrong answer, not a missing feature, and it
# is invisible: the locale picker still says `en-AU`.
config :localize,
  otp_app: :localize_pad,
  default_locale: :en,
  supported_locales: [:en, :"en-AU", :"en-GB", :de, :fr, :es, :ja],
  # The release ships no CLDR data, so a node fetches what it needs the first
  # time it needs it. Lazy rather than at boot: only the locales actually read
  # are downloaded, a transient CDN failure is retried on the next request
  # rather than lasting the life of the node, and a locale gone stale against a
  # newer Localize refreshes itself.
  #
  # The cost is that a failed download is not loud. Localize walks the parent
  # chain and lands on `en`, which for `en-AU` means US conventions with
  # nothing on screen to say so — see `LocalizePad.Locales` on why that
  # particular fallback is the one to watch.
  allow_runtime_locale_download: true

# The retriever is started by this application's own supervision tree rather
# than implicitly by `ex_money`, whose automatic start is deprecated. See
# `LocalizePad.Application`.
#
# Once a day. Open Exchange Rates publishes daily on the free plan, so a
# shorter interval spends the request quota to fetch the same numbers — and
# rates are cached in ETS after retrieval, so every conversion in between is a
# lookup rather than a call.
config :ex_money,
  auto_start_exchange_rate_service: false,
  exchange_rates_retrieve_every: :timer.hours(24)

# Calendrical resolves IANA zone names ("Asia/Tokyo") through whichever
# timezone database the host application installs. Without this, every
# zone-bearing calculation falls back to UTC.
config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
