defmodule Spitegear.LiveGameState do
  @moduledoc """
  Represents the in-memory state of a running GamePoller and provides
  functions that combine DB-backed turn history with live in-flight state.

  `TurnHistory.list_rounds/1` operates only on completed turns in the DB.
  The player whose turn is currently in progress has not been written yet,
  so round completion is invisible to the DB query alone. This module
  bridges that gap.
  """

  alias Spitegear.Turns

  @type t :: %__MODULE__{}

  defstruct game_id: nil,
            view_screen: nil,
            dead_players: [],
            current_turn: nil,
            last_turn_id: nil,
            status: :players_joining,
            view_screen_timer: nil,
            view_screen_polls_remaining: 0,
            moving_announced: false,
            last_round: 0,
            last_stats_round: 0

  @doc "Returns a fresh state struct for `game_id` with all other fields at their initial defaults."
  @spec new(String.t()) :: t()
  def new(game_id), do: %__MODULE__{game_id: game_id}

  @doc """
  Returns the number of completed rounds for `game_id`, accounting for the
  player whose turn is currently in progress but not yet in `turn_history`.

  A round is considered complete when `current_player_name` was already seen
  in the most recent in-progress round — meaning everyone in that round has
  now taken a turn (including the player just now taking theirs).
  """
  @spec completed_rounds(String.t(), String.t() | nil) :: non_neg_integer()
  def completed_rounds(game_id, current_player_name) do
    rounds = Turns.list_rounds(game_id)
    complete_count = Enum.count(rounds, & &1.complete)

    with name when is_binary(name) <- current_player_name,
         %{complete: false, turns: turns} <- List.last(rounds),
         true <- name in Enum.map(turns, & &1.player_name) do
      complete_count + 1
    else
      _ -> complete_count
    end
  end

end
