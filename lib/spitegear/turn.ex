defmodule Spitegear.Turn do
  use Ecto.Schema

  schema "turns" do
    field :game_id, :string
    field :player_name, :string
    field :player, :any, virtual: true
    field :started, :utc_datetime
    field :reminded, :utc_datetime
    field :reminders, :integer, default: 0

    timestamps()
  end
end
