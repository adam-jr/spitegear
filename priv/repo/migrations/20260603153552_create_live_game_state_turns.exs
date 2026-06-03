defmodule Spitegear.Repo.Migrations.CreateLiveGameStateTurns do
  use Ecto.Migration

  def change do
    create table(:live_game_state_turns) do
      add :game_id, :string, null: false
      add :player_name, :string, null: false
      add :started_at, :utc_datetime, null: false
      add :ended_at, :utc_datetime
      add :reminded, :utc_datetime
      add :reminders, :integer, null: false, default: 0
      add :moving_announced, :boolean, null: false, default: false

      timestamps()
    end

    create index(:live_game_state_turns, [:game_id])
  end
end
