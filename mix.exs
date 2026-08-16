defmodule LocalizePad.MixProject do
  use Mix.Project

  def project do
    [
      app: :localize_pad,
      version: "0.1.0",
      # Tempo requires OTP 27+, which puts the floor at Elixir 1.17.
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      dialyzer: [
        plt_add_apps: [:mix, :ex_unit],
        flags: [:error_handling, :unknown, :extra_return, :missing_return]
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {LocalizePad.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.5"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:swoosh, "~> 1.16"},
      {:req, "~> 0.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},

      # The calculation engine. Localize supplies CLDR number/unit/date
      # formatting and locale-aware number parsing; Calendrical parses dates,
      # times and intervals against CLDR patterns; Tempo is the temporal value
      # type; Unity is the unit engine; Money is currency and finance.
      {:localize, "~> 1.2"},
      {:localize_web, "~> 1.1"},
      {:calendrical, "~> 1.2"},
      {:ex_tempo, "~> 1.2"},
      {:unity, "~> 1.1"},
      {:ex_money, "~> 6.2"},

      # Required by Calendrical.TimeZone to resolve IANA zone names.
      {:tzdata, "~> 1.1"},

      # UAX #29 word segmentation, including dictionary-based breaking for the
      # scripts written without word spaces. Needs
      # `mix unicode.string.download.dictionaries` — see `mix setup`.
      {:unicode_string, "~> 2.3"},

      # Static analysis. Both are lint-row-only in CI.
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: [
        "deps.get",
        "localize.download_locales",
        "unicode.string.download.dictionaries",
        "ecto.setup",
        "assets.setup",
        "assets.build"
      ],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      # Locale data is downloaded, not vendored, so the test run primes the
      # cache for every locale in `:supported_locales` before it starts.
      test: [
        "localize.download_locales",
        "unicode.string.download.dictionaries",
        "ecto.create --quiet",
        "ecto.migrate --quiet",
        "test"
      ],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind localize_pad", "esbuild localize_pad"],
      "assets.deploy": [
        "tailwind localize_pad --minify",
        "esbuild localize_pad --minify",
        "phx.digest"
      ],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
