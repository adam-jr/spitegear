defmodule Spitegear.LiveGameState do
  @moduledoc """
  Represents the in-memory state of a running GamePoller and provides
  functions that combine DB-backed turn history with live in-flight state.

  `TurnHistory.list_rounds/1` operates only on completed turns in the DB.
  The player whose turn is currently in progress has not been written yet,
  so round completion is invisible to the DB query alone. This module
  bridges that gap.
  """

  alias Spitegear.Games
  alias Spitegear.Turns

  @type t :: %__MODULE__{}

  @view_screen_max_polls 10

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

  @doc """
  Returns a fresh state struct for `game_id` with all other fields at their
  initial defaults.

      iex> state = Spitegear.LiveGameState.new("42")
      iex> {state.game_id, state.status, state.last_round, state.dead_players}
      {"42", :players_joining, 0, []}

  """
  @spec new(String.t()) :: t()
  def new(game_id), do: %__MODULE__{game_id: game_id}

  @doc """
  Queries the DB for eliminated players and populates `dead_players` in the
  state. Each entry is a plain map `%{name: player_name}` for compatibility
  with the rest of the poller.
  """
  @spec load_dead_players(t()) :: t()
  def load_dead_players(%__MODULE__{game_id: game_id} = state) do
    dead_players = Games.list_deaths(game_id) |> Enum.map(&%{name: &1.player_name})
    %{state | dead_players: dead_players}
  end

  @doc """
  Queries the DB for the current active turn and sets `last_round` using
  `completed_rounds/2`, which accounts for the live player not yet written
  to `turn_history`.
  """
  @spec load_last_round(t()) :: t()
  def load_last_round(%__MODULE__{game_id: game_id} = state) do
    current_turn = Games.get_current_turn(game_id)
    current_player_name = current_turn && current_turn.player && current_turn.player.name
    %{state | last_round: completed_rounds(game_id, current_player_name)}
  end

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

  @doc """
  Resets view-screen polling state when a new turn is detected.

  Sets `last_turn_id` to the newly observed turn, clears any scheduled
  poll timer reference, and restores `view_screen_polls_remaining` to the
  maximum. The caller is responsible for cancelling the old timer before
  calling this.

      iex> state = Spitegear.LiveGameState.new("g1")
      iex> updated = Spitegear.LiveGameState.reset_view_screen_poll(state, "t42")
      iex> {updated.last_turn_id, updated.view_screen_timer, updated.view_screen_polls_remaining}
      {"t42", nil, 10}

  """
  @spec reset_view_screen_poll(t(), String.t()) :: t()
  def reset_view_screen_poll(%__MODULE__{} = game_state, turn_id) do
    %{
      game_state
      | last_turn_id: turn_id,
        view_screen_timer: nil,
        view_screen_polls_remaining: @view_screen_max_polls
    }
  end
end
