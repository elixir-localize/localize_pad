defmodule LocalizePad.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      LocalizePadWeb.Telemetry,
      LocalizePad.Repo,
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

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    LocalizePadWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
