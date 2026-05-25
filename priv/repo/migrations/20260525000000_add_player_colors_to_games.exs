defmodule Spitegear.Repo.Migrations.AddPlayerColorsToGames do
  use Ecto.Migration

  def change do
    alter table(:games) do
      add :player_colors, :map, default: %{}
    end
  end
end
