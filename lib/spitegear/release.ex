defmodule Spitegear.Release do
  @moduledoc false
  @app :spitegear

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  defp load_app, do: Application.load(@app)

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)
end
