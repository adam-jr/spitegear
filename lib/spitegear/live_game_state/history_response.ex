defmodule Spitegear.LiveGameState.HistoryResponse do
  @moduledoc """
  Append-only record of a raw History API response as observed during live
  game tracking.

  A new row is written only when the `turnid` in the response differs from
  the most recently stored response for the game. Unchanged polls produce no
  new row.

  `turn_data` holds the raw map returned by `History.latest_turn/1` — the
  `@attributes` of the most recent turn entry from the wargear.net History
  API endpoint.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "live_game_state_history_responses" do
    field(:game_id, :string)
    field(:turn_data, :map)

    timestamps()
  end
end
