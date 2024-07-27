defmodule Spitegear.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SpitegearWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:spitegear, :dns_cluster_query) || :ignore},
      {DynamicSupervisor, name: GameSupervisor, strategy: :one_for_one},
      {Phoenix.PubSub, name: Spitegear.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: Spitegear.Finch},
      # Start a worker by calling: Spitegear.Worker.start_link(arg)
      # {Spitegear.Worker, arg},
      # Start to serve requests, typically the last entry
      SpitegearWeb.Endpoint,
      Spitegear.Worker.KeepAlive
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Spitegear.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SpitegearWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
