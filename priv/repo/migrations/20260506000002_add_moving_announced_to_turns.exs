defmodule Spitegear.Repo.Migrations.AddMovingAnnouncedToTurns do
  use Ecto.Migration

  def change do
    alter table(:turns) do
      add :moving_announced, :boolean, default: false, null: false
    end
  end
end
