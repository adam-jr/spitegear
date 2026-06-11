defmodule Spitegear.Turn do
  @moduledoc """
  Schema for the `turns` table.

  **Deprecated.** The `turns` table tracked a singleton current-turn row per
  game (upserted on `game_id`). Turn state is now managed in `LiveGameState`
  and persisted via `TurnHistory`. This schema is retained for reference but
  should not be written to by new code.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "turns" do
    field(:game_id, :string)
    field(:player_name, :string)
    field(:player, :any, virtual: true)
    field(:started, :utc_datetime)
    field(:reminded, :utc_datetime)
    field(:reminders, :integer, default: 0)
    field(:moving_announced, :boolean, default: false)

    timestamps()
  end
end
