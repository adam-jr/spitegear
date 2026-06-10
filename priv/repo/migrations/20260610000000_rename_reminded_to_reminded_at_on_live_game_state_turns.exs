defmodule Spitegear.Repo.Migrations.RenameRemindedToRemindedAtOnLiveGameStateTurns do
  use Ecto.Migration

  def change do
    rename table(:live_game_state_turns), :reminded, to: :reminded_at
  end
end
