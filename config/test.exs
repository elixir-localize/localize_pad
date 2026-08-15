import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
# Credentials come from the standard libpq environment variables so the same
# config serves a developer's local Postgres (often a peer-authenticated
# account named after the user) and CI's postgres/postgres container, without
# either having to edit this file.
config :localize_pad, LocalizePad.Repo,
  username: System.get_env("PGUSER", "postgres"),
  password: System.get_env("PGPASSWORD", "postgres"),
  hostname: System.get_env("PGHOST", "localhost"),
  database: "localize_pad_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# A sales tax rate for the suite. There is no correct default in the app
# itself — rates vary by country and, in the US, by state — so the tests state
# the one they assert against.
config :localize_pad, sales_tax: [name: "VAT", rate: 15]

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :localize_pad, LocalizePadWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "tjdkMush6YOMF6Glxcu0jt5FW1OzVZ0bOJVl75JhUAxh8k8MRHNktHU5NYIiicJM",
  server: false

# In test we don't send emails
config :localize_pad, LocalizePad.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
