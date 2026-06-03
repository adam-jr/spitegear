defmodule Spitegear.Game do
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "games" do
    field(:game_id, :string)
    field(:url, :string)
    field(:game_name, :string)
    field(:board_name, :string)
    field(:created, :string)
    field(:finished, :string)
    field(:winners, {:array, :string}, default: [])
    field(:player_colors, :map, default: %{})
    field(:discovered, :boolean, default: false)

    timestamps()
  end
end
