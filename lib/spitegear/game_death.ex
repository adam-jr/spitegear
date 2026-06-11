defmodule Spitegear.GameDeath do
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "game_deaths" do
    field(:game_id, :string)
    field(:player_name, :string)
    field(:eliminated_at, :utc_datetime)
    field(:inferred, :boolean, default: false)

    timestamps()
  end
end
