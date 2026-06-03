defmodule Spitegear.LiveGameState.Turn do
  @moduledoc """
  Append-only record of a single turn observed during live game tracking.
  Combines turn-boundary detection with per-turn reminder state.

  Turns are inferred by polling the wargear.net History API and ViewScreen
  while a game is in progress. In most games, fog of war hides the log until
  the game ends, so turn boundaries cannot be read directly.

  Instead:
  - A turn *starts* the first time a player is observed as the active player
  - A turn *ends* the first time a different active player is detected

  As a result, `started_at` and `ended_at` reflect when the change was
  *detected*, not when the move was actually submitted. Their accuracy is
  bounded by the polling interval.

  For games without fog of war, the full log is available immediately.
  However, this polling-based approach is used consistently across all games
  for simplicity. After a game ends and the map is unfogged, canonical turn
  data can be reconstructed from the final log snapshot for precise analysis.

  ## Migration from `TurnHistory`

  The legacy `Spitegear.TurnHistory` schema tracks turn boundaries but does
  not include reminder state.

  Use `to_live_game_state_turn/1` to convert existing records when
  backfilling. Reminder-related fields (`reminded`, `reminders`,
  `moving_announced`) will be initialized to defaults, since that data was
  not captured historically.
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
