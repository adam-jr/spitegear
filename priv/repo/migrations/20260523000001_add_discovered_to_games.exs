defmodule Spitegear.Repo.Migrations.AddDiscoveredToGames do
  use Ecto.Migration

  def change do
    alter table(:games) do
      add :discovered, :boolean, null: false, default: false
    end
  end
end
