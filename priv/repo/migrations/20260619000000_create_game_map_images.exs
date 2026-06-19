defmodule Spitegear.Repo.Migrations.CreateGameMapImages do
  use Ecto.Migration

  def change do
    create table(:game_map_images) do
      add :game_id, :string, null: false
      add :image, :binary, null: false
      add :content_type, :string, null: false, default: "image/png"

      timestamps()
    end

    create unique_index(:game_map_images, [:game_id])
  end
end
