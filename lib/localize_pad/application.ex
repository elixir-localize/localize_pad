defmodule LocalizePad.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [LocalizePadWeb.Telemetry] ++
        repo() ++
        exchange_rates() ++
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

  # Only when there is an app id to authenticate with. Started here rather than
  # by `ex_money` itself, whose implicit start is deprecated; without a key the
  # retriever would poll a service that will refuse it, once a day, forever.
  defp exchange_rates do
    if Application.get_env(:ex_money, :open_exchange_rates_app_id) do
      [Money.ExchangeRates.Retriever]
    else
      []
    end
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
