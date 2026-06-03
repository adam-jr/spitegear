defmodule Spitegear.TurnHistory do
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "turn_history" do
    field(:game_id, :string)
    field(:player_name, :string)
    field(:started, :utc_datetime)
    field(:ended, :utc_datetime)

    timestamps()
  end
end
