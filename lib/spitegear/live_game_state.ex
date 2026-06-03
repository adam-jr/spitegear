defmodule Spitegear.LiveGameState do
  @moduledoc """
  Represents the in-memory state of a running GamePoller and provides
  functions that combine DB-backed turn history with live in-flight state.

  `TurnHistory.list_rounds/1` operates only on completed turns in the DB.
  The player whose turn is currently in progress has not been written yet,
  so round completion is invisible to the DB query alone. This module
  bridges that gap.
  """

  require Logger

  alias Spitegear.Games
  alias Spitegear.MessageTemplates
  alias Spitegear.PubSub
  alias Spitegear.Slack.Message
  alias Spitegear.Turn
  alias Spitegear.Turns
  alias Spitegear.Worker.GamePoller.TurnLogic

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

  @doc """
  Records the current turn to `turn_history` if one exists, then returns
  state unchanged. No-op when `current_turn` is nil.
  """
  @spec finish_current_turn(t()) :: t()
  def finish_current_turn(%__MODULE__{current_turn: nil} = state), do: state

  def finish_current_turn(%__MODULE__{} = state) do
    Games.finish_turn(state.current_turn, DateTime.utc_now() |> DateTime.truncate(:second))
    state
  end

  @doc """
  Detects players who were skipped in turn order between the previous and
  current player, records them as eliminated in the DB, and adds them to
  `dead_players` in the state. No-op when `current_turn` is nil.
  """
  @spec infer_deaths_from_skip(t()) :: t()
  def infer_deaths_from_skip(%__MODULE__{current_turn: nil} = state), do: state

  def infer_deaths_from_skip(%__MODULE__{} = state) do
    prev_name = state.current_turn.player.name
    curr_name = state.view_screen.current_player.name
    known_dead = MapSet.new(state.dead_players, & &1.name)

    alive_players =
      Enum.reject(state.view_screen.players, fn p ->
        MapSet.member?(known_dead, p.name) or p.eliminated? or p.winner?
      end)

    n = length(alive_players)
    prev_idx = Enum.find_index(alive_players, &(&1.name == prev_name))
    curr_idx = Enum.find_index(alive_players, &(&1.name == curr_name))

    alive_players
    |> TurnLogic.skipped_players(n, prev_idx, curr_idx)
    |> record_inferred_deaths(state)
  end

  @doc """
  Computes completed rounds for the game, announces a new round to Slack if
  one has completed, and posts turn stats every 5 rounds. Updates
  `last_round` and `last_stats_round` in state accordingly.
  """
  @spec update_rounds(t()) :: t()
  def update_rounds(%__MODULE__{} = state) do
    current_player_name =
      state.view_screen.current_player && state.view_screen.current_player.name

    completed = completed_rounds(state.game_id, current_player_name)

    state
    |> maybe_announce_round(completed)
    |> maybe_post_round_stats(completed)
  end

  @doc """
  Sends the "it's your turn" Slack notification for the player shown in
  `view_screen`. Returns state unchanged.
  """
  @spec announce_next_turn(t()) :: t()
  def announce_next_turn(%__MODULE__{} = state) do
    player = state.view_screen.current_player
    round = state.last_round + 1
    turn_number = Games.completed_turn_count(state.game_id) + 1
    Logger.info("Notifying #{player.name} of turn (round #{round}, turn #{turn_number})...")

    text =
      MessageTemplates.next_turn(
        player,
        state.game_id,
        round,
        turn_number,
        state.view_screen.game_name
      )

    PubSub.msg(:spitegear, text)
    state
  end

  @doc """
  Creates a new `Turn` record for the current view-screen player, persists
  it, and updates `current_turn` and `moving_announced` in state.
  """
  @spec start_new_turn(t()) :: t()
  def start_new_turn(%__MODULE__{} = state) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    turn = %Turn{
      game_id: state.game_id,
      player: state.view_screen.current_player,
      started: now,
      reminded: now,
      reminders: 0
    }

    Games.upsert_turn(turn)
    %{state | current_turn: turn, moving_announced: false}
  end

  # --- Private ---

  defp maybe_announce_round(%__MODULE__{last_round: last_round} = state, completed)
       when completed > last_round do
    text = MessageTemplates.round_complete(state.game_id, completed, state.view_screen.game_name)
    PubSub.msg(:spitegear, text)
    %{state | last_round: completed}
  end

  defp maybe_announce_round(state, _completed), do: state

  defp maybe_post_round_stats(state, completed) do
    if completed > 0 && rem(completed, 5) == 0 && completed != state.last_stats_round do
      stats = Games.turn_stats(state.game_id)
      blocks = Message.blocks(:turn_stats, stats, state.game_id, completed)
      fallback = Message.text(:turn_stats, stats, state.game_id, completed)
      PubSub.msg(:spitegear_test, type: :turn_stats, payload: {blocks, fallback})
      %{state | last_stats_round: completed}
    else
      state
    end
  end

  defp record_inferred_deaths([], state), do: state

  defp record_inferred_deaths(newly_dead, state) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Enum.each(newly_dead, fn player ->
      Logger.info("#{__MODULE__} inferring #{player.name} dead (skipped in turn order)")
      Games.record_death(state.game_id, player.name, now)

      unless state.view_screen.fogged? do
        text = MessageTemplates.player_died(player, state.game_id, state.view_screen.game_name)
        PubSub.msg(:spitegear_test, text)
      end
    end)

    %{state | dead_players: Enum.uniq_by(state.dead_players ++ newly_dead, & &1.name)}
  end
end
