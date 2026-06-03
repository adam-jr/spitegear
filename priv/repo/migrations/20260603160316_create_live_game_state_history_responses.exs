defmodule Spitegear.Repo.Migrations.CreateLiveGameStateHistoryResponses do
  use Ecto.Migration

  def change do
    create table(:live_game_state_history_responses) do
      add :game_id, :string, null: false
      add :turn_data, :map, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:live_game_state_history_responses, [:game_id])
  end
end
