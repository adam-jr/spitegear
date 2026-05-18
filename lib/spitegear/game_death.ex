defmodule Spitegear.GameDeath do
  use Ecto.Schema

  schema "game_deaths" do
    field(:game_id, :string)
    field(:player_name, :string)
    field(:eliminated_at, :utc_datetime)

    timestamps()
  end
end
