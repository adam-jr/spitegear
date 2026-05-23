defmodule Spitegear.Repo.Migrations.CreateGameLogEvents do
  use Ecto.Migration

  def change do
    create table(:game_log_events) do
      add :game_id, :string, null: false
      add :log_seq, :integer, null: false
      add :occurred_at, :string
      add :seat, :integer
      add :player_name, :string
      add :event_type, :string, null: false
      add :raw_action, :string, null: false
      add :attacker, :string
      add :defender, :string
      add :territory_from, :string
      add :territory_to, :string
      add :units, :integer
      add :attacker_dice, :string
      add :defender_dice, :string
      add :battle_mod, :string
      add :attacker_losses, :integer
      add :defender_losses, :integer
      add :turn_id, :integer

      timestamps()
    end

    create unique_index(:game_log_events, [:game_id, :log_seq])
    create index(:game_log_events, [:game_id])
    create index(:game_log_events, [:event_type])
  end
end
