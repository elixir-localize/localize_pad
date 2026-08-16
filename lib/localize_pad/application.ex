defmodule LocalizePad.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Before anything can read a locale. A release ships no locale data — see
    # `LocalizePad.Locales.ensure_downloaded/0` — and dev and test are
    # provisioned by `mix setup` instead, so this is off unless configured.
    if Application.get_env(:localize_pad, :download_locales_on_start, false) do
      LocalizePad.Locales.ensure_downloaded()
    end

    children =
      [LocalizePadWeb.Telemetry] ++
        repo() ++
        [
          {DNSCluster, query: Application.get_env(:localize_pad, :dns_cluster_query) || :ignore},
          {Phoenix.PubSub, name: LocalizePad.PubSub},
          # Start a worker by calling: LocalizePad.Worker.start_link(arg)
          # {LocalizePad.Worker, arg},
          # Start to serve requests, typically the last entry
          LocalizePadWeb.Endpoint
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: LocalizePad.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # The database is optional until accounts arrive. Dev and test configure a
  # repository and get one; a production deployment with no `DATABASE_URL`
  # starts without it rather than refusing to boot. See `config/runtime.exs`.
  defp repo do
    if Application.get_env(:localize_pad, :start_repo, true) do
      [LocalizePad.Repo]
    else
      []
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    LocalizePadWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
