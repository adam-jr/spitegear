defmodule Spitegear.Repo.Migrations.CreateGameDeaths do
  use Ecto.Migration

  def change do
    create table(:game_deaths) do
      add :game_id, :string, null: false
      add :player_name, :string, null: false
      add :eliminated_at, :utc_datetime, null: false

      timestamps()
    end

    create index(:game_deaths, [:game_id])
    create unique_index(:game_deaths, [:game_id, :player_name])
  end
end
