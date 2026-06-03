defmodule Spitegear.LiveGameState.Turn do
  @moduledoc """
  Append-only record of a single turn as observed during live game tracking,
  combining turn-boundary detection with per-turn reminder state.

  Turns are detected by polling the wargear.net History API endpoint and
  ViewScreen while the game is in progress. Because most wargear games use fog
  of war, the game log is hidden until the game ends and the map is unfogged.
  Turn boundaries must therefore be back-inferred from polling: a turn is
  considered to have started the first time a player is seen as the active
  player, and ended the first time a different player is detected. As a result,
  `started_at` and `ended_at` reflect when the change was *detected* rather than
  the exact moment the move was submitted, and carry inherent imprecision
  proportional to the polling interval.

  Games without fog of war do have the full log available from the start, but
  for simplicity this live tracking approach is used uniformly regardless of fog
  settings. Once a game ends and the log is unfogged, the canonical turn data
  can be read from the log snapshot for more precise historical analysis.

  ## Migration from `TurnHistory`

  The legacy `Spitegear.TurnHistory` schema tracks the same turn-boundary data
  but without reminder state. Use `to_live_game_state_turn/1` to convert a
  `TurnHistory` record when backfilling. Reminder fields (`reminded`,
  `reminders`, `moving_announced`) will be set to defaults, as that data was
  not captured at the time.
  """

  use Ecto.Schema

  alias Spitegear.TurnHistory

  @type t :: %__MODULE__{}

  schema "live_game_state_turns" do
    field(:game_id, :string)
    field(:player_name, :string)
    field(:started_at, :utc_datetime)
    field(:ended_at, :utc_datetime)
    field(:reminded, :utc_datetime)
    field(:reminders, :integer, default: 0)
    field(:moving_announced, :boolean, default: false)

    timestamps()
  end

  @doc """
  Converts a `TurnHistory` record to a `LiveGameState.Turn` struct suitable
  for insertion when backfilling the new table from legacy data.

  Reminder fields are unavailable in `TurnHistory` and will be left at their
  defaults (`reminders: 0`, `moving_announced: false`, `reminded: nil`).
  """
  @spec to_live_game_state_turn(TurnHistory.t()) :: t()
  def to_live_game_state_turn(%TurnHistory{} = th) do
    %__MODULE__{
      game_id: th.game_id,
      player_name: th.player_name,
      started_at: th.started,
      ended_at: th.ended
    }
  end
end
