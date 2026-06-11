defmodule Spitegear.Repo.Migrations.DropDiscoveredFromGames do
  use Ecto.Migration

  def change do
    alter table(:games) do
      remove :discovered, :boolean, default: false
    end
  end
end
