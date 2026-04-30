defmodule Spitegear.Game do
  use Ecto.Schema

  schema "games" do
    field :game_id, :string
    field :url, :string
    field :game_name, :string
    field :board_name, :string
    field :created, :string
    field :finished, :string
    field :winners, {:array, :string}, default: []

    timestamps()
  end
end
