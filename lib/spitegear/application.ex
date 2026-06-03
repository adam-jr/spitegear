defmodule Spitegear.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SpitegearWeb.Telemetry,
      Spitegear.Repo,
      {DNSCluster, query: Application.get_env(:spitegear, :dns_cluster_query) || :ignore},
      {DynamicSupervisor, name: GameSupervisor, strategy: :one_for_one},
      {Phoenix.PubSub, name: Spitegear.PubSub},
      {Finch, name: Spitegear.Finch},
      SpitegearWeb.Endpoint,
      Spitegear.Worker.SlackMessenger,
      Spitegear.Scheduler,
      Supervisor.child_spec({Task, &Spitegear.Games.resume_games/0}, id: :resume_games),
      Supervisor.child_spec({Task, &Spitegear.Games.resume_new_pollers/0}, id: :resume_new_pollers)
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Spitegear.Supervisor]

    with {:ok, _} = result <- Supervisor.start_link(children, opts) do
      :logger.add_handler(:slack_errors, Spitegear.Logger.SlackErrorHandler, %{level: :error})
      result
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SpitegearWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
