defmodule Spitegear.LiveGameState do
  @moduledoc """
  Struct representing the known live state of a single active game.

  Tracks the current and previous turns as persisted `LiveGameState.Turn`
  records. Both fields are loaded from the database — they reflect what has
  already been written, not raw API responses.

  Use `new/1` to build an initial struct for a game, or `load_recent_turns/1`
  to refresh an existing struct's turn fields (e.g. after a turn change is
  recorded by `Turns.record_turn_start/2`).
  """

  alias Spitegear.LiveGameState.Turn
  alias Spitegear.LiveGameState.Turns

  @type t :: %__MODULE__{
          game_id: String.t() | nil,
          current_turn: Turn.t() | nil,
          prev_turn: Turn.t() | nil
        }

  defstruct game_id: nil,
            current_turn: nil,
            prev_turn: nil

  @doc """
  Returns a new `LiveGameState` for `game_id` with `current_turn` and
  `prev_turn` loaded from the database.

      iex> state = Spitegear.LiveGameState.new("42")
      iex> state.game_id
      "42"

  """
  @spec new(String.t()) :: t()
  def new(game_id), do: load_recent_turns(%__MODULE__{game_id: game_id})

  @doc """
  Hydrates `current_turn` and `prev_turn` on the given struct from the
  database. Preserves all other fields on `state`.

  - `current_turn` — the open turn (ended_at IS NULL), or `nil`
  - `prev_turn` — the most recently closed turn, or `nil`

  Call this after `Turns.record_turn_start/2` to keep the struct current
  without discarding any other state already stored on it.
  """
  @spec load_recent_turns(t()) :: t()
  def load_recent_turns(%__MODULE__{game_id: game_id} = state) do
    %{
      state
      | current_turn: Turns.get_open_turn(game_id),
        prev_turn: Turns.get_last_closed_turn(game_id)
    }
  end
end
