defmodule Spitegear.Repo.Migrations.AddTurnIdToGameMapImages do
  use Ecto.Migration

  def up do
    drop unique_index(:game_map_images, [:game_id])
    execute("TRUNCATE game_map_images")

    alter table(:game_map_images) do
      add :turn_id, references(:live_game_state_turns, on_delete: :delete_all), null: false
    end

    create unique_index(:game_map_images, [:game_id, :turn_id])
  end

  def down do
    drop unique_index(:game_map_images, [:game_id, :turn_id])

    alter table(:game_map_images) do
      remove :turn_id
    end

    create unique_index(:game_map_images, [:game_id])
  end
end
