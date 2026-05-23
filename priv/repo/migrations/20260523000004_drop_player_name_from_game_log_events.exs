defmodule Spitegear.Repo.Migrations.DropPlayerNameFromGameLogEvents do
  use Ecto.Migration

  def change do
    alter table(:game_log_events) do
      remove :player_name, :string
    end
  end
end
