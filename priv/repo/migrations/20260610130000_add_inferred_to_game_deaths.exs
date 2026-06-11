defmodule Spitegear.Repo.Migrations.AddInferredToGameDeaths do
  use Ecto.Migration

  def change do
    alter table(:game_deaths) do
      add :inferred, :boolean, default: false, null: false
    end
  end
end
