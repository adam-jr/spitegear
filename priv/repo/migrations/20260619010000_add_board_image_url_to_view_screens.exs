defmodule Spitegear.Repo.Migrations.AddBoardImageUrlToViewScreens do
  use Ecto.Migration

  def change do
    alter table(:live_game_state_view_screens) do
      add :board_image_url, :string
    end
  end
end
