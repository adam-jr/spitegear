defmodule Spitegear.Repo.Migrations.CreateGameLogSnapshots do
  use Ecto.Migration

  def change do
    create table(:game_log_snapshots) do
      add :game_id, :integer, null: false
      add :html, :text, null: false
      add :fetched_at, :utc_datetime_usec, null: false

      timestamps()
    end

    create unique_index(:game_log_snapshots, [:game_id])
  end
end
