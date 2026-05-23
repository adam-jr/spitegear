defmodule Spitegear.Repo.Migrations.RenameAttackerToPlayerOnGameLogEvents do
  use Ecto.Migration

  def change do
    rename table(:game_log_events), :attacker, to: :player
  end
end
