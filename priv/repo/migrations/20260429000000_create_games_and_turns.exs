defmodule Spitegear.Repo.Migrations.CreateGamesAndTurns do
  use Ecto.Migration

  def change do
    create table(:games) do
      add :game_id, :string, null: false
      add :url, :string
      add :game_name, :string
      add :board_name, :string
      add :created, :string
      add :finished, :string

      add :winners, {:array, :string}, default: []

      timestamps()
    end

    create unique_index(:games, [:game_id])

    create table(:turns) do
      add :game_id, :string, null: false
      add :player_name, :string
      add :started, :utc_datetime
      add :reminded, :utc_datetime
      add :reminders, :integer, default: 0

      timestamps()
    end

    create unique_index(:turns, [:game_id])
  end
end
