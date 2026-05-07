defmodule Spitegear.Repo.Migrations.CreateTurnHistory do
  use Ecto.Migration

  def change do
    create table(:turn_history) do
      add :game_id, :string, null: false
      add :player_name, :string, null: false
      add :started, :utc_datetime
      add :ended, :utc_datetime

      timestamps()
    end

    create index(:turn_history, [:game_id])
  end
end
