defmodule Spitegear.LiveGameState do
  @moduledoc """
  Struct representing the known live state of a single active game.

  Tracks the current and previous turns, view screen snapshots, and history
  API responses as persisted DB records. All fields are loaded from the
  database — they reflect what has already been written, not raw API responses.

  Use `new/1` to build an initial struct for a game, or `load_recent_turns/1`
  to refresh an existing struct's fields (e.g. after a turn change or a new
  snapshot is recorded).
  """

  alias Spitegear.LiveGameState.HistoryResponses
  alias Spitegear.LiveGameState.Turn
  alias Spitegear.LiveGameState.Turns
  alias Spitegear.LiveGameState.ViewScreens
  alias Spitegear.LiveGameState.WargearHistoryApiResponseDb
  alias Spitegear.LiveGameState.WargearViewScreenDb

  @type t :: %__MODULE__{
          game_id: String.t() | nil,
          current_turn: Turn.t() | nil,
          prev_turn: Turn.t() | nil,
          current_view_screen: WargearViewScreenDb.t() | nil,
          prev_view_screen: WargearViewScreenDb.t() | nil,
          current_history_response: WargearHistoryApiResponseDb.t() | nil,
          prev_history_response: WargearHistoryApiResponseDb.t() | nil
        }

  defstruct game_id: nil,
            current_turn: nil,
            prev_turn: nil,
            current_view_screen: nil,
            prev_view_screen: nil,
            current_history_response: nil,
            prev_history_response: nil

  @doc """
  Returns a new `LiveGameState` for `game_id` with all fields loaded from
  the database.

      iex> state = Spitegear.LiveGameState.new("42")
      iex> state.game_id
      "42"

  """
  @spec new(String.t()) :: t()
  def new(game_id), do: load_recent_turns(%__MODULE__{game_id: game_id})

  @doc """
  Hydrates all DB-backed fields on the given struct from the database.
  Preserves all other fields on `state`.

  Loads:
  - `current_turn` / `prev_turn` — open and last-closed `LiveGameState.Turn`
  - `current_view_screen` / `prev_view_screen` — two most recent `WargearViewScreenDb` snapshots
  - `current_history_response` / `prev_history_response` — two most recent `WargearHistoryApiResponseDb` records

  Call this after recording a turn, view screen, or history response to keep
  the struct current without discarding any other state already stored on it.
  """
  @spec load_recent_turns(t()) :: t()
  def load_recent_turns(%__MODULE__{game_id: game_id} = state) do
    %{
      state
      | current_turn: Turns.get_open_turn(game_id),
        prev_turn: Turns.get_last_closed_turn(game_id),
        current_view_screen: ViewScreens.get_latest(game_id),
        prev_view_screen: ViewScreens.get_prev(game_id),
        current_history_response: HistoryResponses.get_latest(game_id),
        prev_history_response: HistoryResponses.get_prev(game_id)
    }
  end
end
