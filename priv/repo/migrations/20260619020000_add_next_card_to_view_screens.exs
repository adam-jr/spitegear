defmodule Spitegear.Repo.Migrations.AddNextCardToViewScreens do
  use Ecto.Migration

  def change do
    alter table(:live_game_state_view_screens) do
      add(:next_card, :string)
    end
  end
end
