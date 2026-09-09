defmodule Spitegear.Repo.Migrations.AddTotalFogToGames do
  use Ecto.Migration

  def change do
    alter table(:games) do
      add :total_fog, :boolean, default: false, null: false
    end
  end
end
