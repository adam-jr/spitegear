defmodule Spitegear.Repo.Migrations.CreateLiveGameStateViewScreens do
  use Ecto.Migration

  def change do
    create table(:live_game_state_view_screens) do
      add :game_id, :string, null: false
      add :game_name, :string
      add :board_name, :string
      add :created, :string
      add :finished, :string
      add :current_player_name, :string
      add :players, {:array, :map}, null: false, default: []
      add :eliminated, {:array, :string}, null: false, default: []
      add :winners, {:array, :string}, null: false, default: []
      add :fogged, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create index(:live_game_state_view_screens, [:game_id])
  end
end
