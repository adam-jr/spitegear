defmodule Spitegear.Repo.Migrations.MakeGameMapTurnIdNullable do
  use Ecto.Migration

  def up do
    drop unique_index(:game_map_images, [:game_id, :turn_id])

    execute "ALTER TABLE game_map_images ALTER COLUMN turn_id DROP NOT NULL"

    # One image per (game, turn) for mid-game snapshots
    create unique_index(:game_map_images, [:game_id, :turn_id],
             where: "turn_id IS NOT NULL",
             name: :game_map_images_game_id_turn_id_index
           )

    # One final image per game (turn_id IS NULL = endgame snapshot)
    create unique_index(:game_map_images, [:game_id],
             where: "turn_id IS NULL",
             name: :game_map_images_game_id_final_index
           )
  end

  def down do
    drop index(:game_map_images, [:game_id, :turn_id],
           where: "turn_id IS NOT NULL",
           name: :game_map_images_game_id_turn_id_index
         )

    drop index(:game_map_images, [:game_id],
           where: "turn_id IS NULL",
           name: :game_map_images_game_id_final_index
         )

    execute "ALTER TABLE game_map_images ALTER COLUMN turn_id SET NOT NULL"

    create unique_index(:game_map_images, [:game_id, :turn_id])
  end
end
