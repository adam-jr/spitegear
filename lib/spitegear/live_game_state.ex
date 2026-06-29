defmodule Spitegear.LiveGameState do
  @moduledoc """
  Struct representing the known live state of a single active game.

  Tracks the current and previous turns, view screen snapshots, and history
  API responses as persisted DB records. All fields are loaded from the
  database — they reflect what has already been written, not raw API responses.

  Use `new/1` to build an initial struct for a game, or `hydrate/1` to
  refresh an existing struct's fields (e.g. after restart).

  For history API updates, call the pipeline steps in order:

      state
      |> LiveGameState.record_changed_history_response(turn_data)
      |> LiveGameState.send_reminder()
      |> LiveGameState.announce_moving()

  For view screen updates, call the pipeline steps in order:

      state
      |> LiveGameState.record_changed_view_screen_db(view_screen)
      |> LiveGameState.advance_turn()
      |> LiveGameState.fetch_board_image_if_advanced()
      |> LiveGameState.fetch_log_if_unfogged()
      |> LiveGameState.announce_next_round()
      |> LiveGameState.announce_next_turn()
      |> LiveGameState.infer_deaths_from_skip()
      |> LiveGameState.detect_eliminations()
      |> LiveGameState.announce_winners()

  Each step is a no-op when its precondition is not met, so the pipeline
  always returns a valid struct.
  """

  require Logger

  alias Spitegear.GameDeaths
  alias Spitegear.LiveGameState.HistoryResponses
  alias Spitegear.LiveGameState.Turn
  alias Spitegear.LiveGameState.Turns
  alias Spitegear.LiveGameState.ViewScreen
  alias Spitegear.LiveGameState.ViewScreens
  alias Spitegear.LiveGameState.WargearHistoryApiResponseDb
  alias Spitegear.MessageTemplates
  alias Spitegear.PubSub
  alias Spitegear.Wargear.HTTP.ViewScreen, as: HTTPViewScreen
  alias Spitegear.Worker.GamePoller

  @type t :: %__MODULE__{
          game_id: String.t() | nil,
          current_turn: Turn.t() | nil,
          prev_turn: Turn.t() | nil,
          current_view_screen: ViewScreen.t() | nil,
          prev_view_screen: ViewScreen.t() | nil,
          current_api_response: WargearHistoryApiResponseDb.t() | nil,
          prev_api_response: WargearHistoryApiResponseDb.t() | nil,
          history_changed: boolean(),
          view_screen_changed: boolean(),
          turn_advanced: boolean()
        }

  defstruct game_id: nil,
            current_turn: nil,
            prev_turn: nil,
            current_view_screen: nil,
            prev_view_screen: nil,
            current_api_response: nil,
            prev_api_response: nil,
            history_changed: false,
            view_screen_changed: false,
            turn_advanced: false

  @doc """
  Returns a new `LiveGameState` for `game_id` with all fields loaded from
  the database.

      iex> state = Spitegear.LiveGameState.new("42")
      iex> state.game_id
      "42"

  """
  @spec new(String.t()) :: t()
  def new(game_id), do: hydrate(%__MODULE__{game_id: game_id})

  @doc """
  Hydrates all DB-backed fields on the given struct from the database.
  Loads turns, view screen snapshots, and history responses.
  Preserves transient dispatch flags (`view_screen_changed`, `turn_advanced`).

  Call this on startup or after a crash restart. For ongoing updates, use the
  individual pipeline steps, which update the struct in-memory without an extra
  DB read.
  """
  @spec hydrate(t()) :: t()
  def hydrate(%__MODULE__{game_id: game_id} = state) do
    %{
      state
      | current_turn: Turns.get_open_turn(game_id),
        prev_turn: Turns.get_last_closed_turn(game_id),
        current_view_screen: ViewScreens.get_latest(game_id),
        prev_view_screen: ViewScreens.get_prev(game_id),
        current_api_response: HistoryResponses.get_latest(game_id),
        prev_api_response: HistoryResponses.get_prev(game_id)
    }
  end

  @doc """
  Processes a raw History API response. Persists it if the `turnid` has
  changed, then shifts `current_api_response` → `prev_api_response`,
  sets `current_api_response` to the new record, and sets
  `history_changed: true`. Sets `history_changed: false` when the response
  is identical to the last stored one or if the insert fails.
  """
  @spec record_changed_history_response(t(), map()) :: t()
  def record_changed_history_response(%__MODULE__{} = state, turn_data) do
    case HistoryResponses.record_if_changed(state.game_id, turn_data) do
      {:ok, :unchanged} ->
        %{state | history_changed: false}

      {:ok, record} ->
        %{
          state
          | prev_api_response: state.current_api_response,
            current_api_response: record,
            history_changed: true
        }

      {:error, _} ->
        Logger.error("#{__MODULE__} failed to record history response for game #{state.game_id}")
        %{state | history_changed: false}
    end
  end

  @doc """
  Persists the view screen if it differs from the latest stored snapshot.

  When a change is detected, shifts `current_view_screen` → `prev_view_screen`,
  sets `current_view_screen` to the newly-inserted snapshot, and sets
  `view_screen_changed: true`. Sets `view_screen_changed: false` when the
  screen is unchanged or the insert fails.
  """
  @spec record_changed_view_screen_db(t(), HTTPViewScreen.t()) :: t()
  def record_changed_view_screen_db(%__MODULE__{} = state, %HTTPViewScreen{} = view_screen) do
    case ViewScreens.record_if_changed(view_screen) do
      {:ok, :unchanged} ->
        %{state | view_screen_changed: false}

      {:ok, snapshot} ->
        %{
          state
          | current_view_screen: snapshot,
            prev_view_screen: state.current_view_screen,
            view_screen_changed: true
        }

      {:error, _} ->
        Logger.error("#{__MODULE__} failed to record view screen for game #{state.game_id}")
        %{state | view_screen_changed: false}
    end
  end

  @doc """
  Casts an async board image fetch to the `GamePoller` for this game if the
  turn just advanced on an unfogged game. The poller handles retries with backoff.

  No-op when `turn_advanced` is `false` or the game is fogged.
  """
  @spec fetch_board_image_if_advanced(t()) :: t()
  def fetch_board_image_if_advanced(%__MODULE__{turn_advanced: false} = state), do: state

  def fetch_board_image_if_advanced(
        %__MODULE__{current_view_screen: %ViewScreen{fogged?: true}} = state
      ),
      do: state

  def fetch_board_image_if_advanced(%__MODULE__{} = state) do
    url = state.current_view_screen.board_image_url
    turn_id = state.current_turn && state.current_turn.id

    if url && turn_id do
      GenServer.cast(GamePoller.name(state.game_id), {:fetch_board_image, url, turn_id})
    end

    state
  end

  @doc """
  Records a turn transition when the active player in `current_view_screen`
  differs from the player in `current_turn`.

  On a player change:
  1. Finishes the current open turn via `Turns.finish_turn/1`, setting
     `ended_at` in the DB and shifting `current_turn` → `prev_turn`.
  2. Starts a new turn via `Turns.start_turn/2` and sets it as `current_turn`.
  3. Sets `turn_advanced: true`.

  No-op — setting `turn_advanced: false` — when the view screen was unchanged
  or `current_view_screen` is nil. When `current_turn` is nil (no prior turn),
  skips the finish step and starts a new turn directly. When the active player
  matches `current_turn.player_name`, no transition is recorded.
  """
  @spec advance_turn(t()) :: t()
  def advance_turn(%__MODULE__{view_screen_changed: false} = state),
    do: %{state | turn_advanced: false}

  def advance_turn(%__MODULE__{current_view_screen: nil} = state),
    do: %{state | turn_advanced: false}

  # Game over — no current player means winners are present; let announce_winners handle it.
  def advance_turn(
        %__MODULE__{current_view_screen: %ViewScreen{current_player_name: nil}} = state
      ),
      do: %{state | turn_advanced: false}

  def advance_turn(
        %__MODULE__{
          current_view_screen: %ViewScreen{current_player_name: player_name},
          current_turn: %Turn{player_name: player_name}
        } =
          state
      ),
      do: %{state | turn_advanced: false}

  def advance_turn(%__MODULE__{} = state) do
    new_player = state.current_view_screen.current_player_name

    with {:ok, finished_prev} <- finish_prev_turn(state.current_turn),
         {:ok, new_turn} <- Turns.start_turn(state.game_id, new_player) do
      %{state | prev_turn: finished_prev, current_turn: new_turn, turn_advanced: true}
    else
      _ ->
        Logger.error("#{__MODULE__} failed to advance turn for game #{state.game_id}")
        %{state | turn_advanced: false}
    end
  end

  defp finish_prev_turn(nil), do: {:ok, nil}
  defp finish_prev_turn(turn), do: Turns.finish_turn(turn)

  @doc """
  Sends `GenServer.cast(self(), :fetch_log)` to the calling process when a turn
  just advanced on a non-fogged game, so the poller can re-fetch and process the
  event log asynchronously.

  No-op when `turn_advanced` is `false` or the current view screen is fogged.
  """
  @spec fetch_log_if_unfogged(t()) :: t()
  def fetch_log_if_unfogged(%__MODULE__{turn_advanced: false} = state), do: state
  def fetch_log_if_unfogged(%__MODULE__{current_view_screen: %{fogged?: true}} = state), do: state

  def fetch_log_if_unfogged(%__MODULE__{} = state) do
    GenServer.cast(self(), :fetch_log)
    state
  end

  @doc """
  Publishes a "Round N starting" message to `:spitegear_test` when
  `Turns.round_info/1` reports `new_round_starting?: true`.

  This is the only pipeline step that reads from the database.

  No-op when `turn_advanced` is `false`.
  """
  @spec announce_next_round(t()) :: t()
  def announce_next_round(%__MODULE__{turn_advanced: false} = state), do: state
  def announce_next_round(%__MODULE__{current_view_screen: nil} = state), do: state

  def announce_next_round(%__MODULE__{current_view_screen: %ViewScreen{} = vs} = state) do
    %{new_round_starting?: new_round?, current_round: round} = Turns.round_info(state.game_id)

    if new_round? do
      completed_round = round - 1

      text =
        MessageTemplates.round_complete(
          vs.game_id,
          completed_round,
          vs.game_name
        )

      PubSub.msg(:spitegear, text)
    end

    state
  end

  @doc """
  Publishes the next-turn Slack notification to `:spitegear` when a turn just
  advanced. Reads `round_info` from the DB and resolves the player's slack name
  from the current view screen's player list.

  No-op when `turn_advanced` is `false` or `current_turn` is `nil`.
  """
  @spec announce_next_turn(t()) :: t()
  def announce_next_turn(%__MODULE__{turn_advanced: false} = state), do: state
  def announce_next_turn(%__MODULE__{current_turn: nil} = state), do: state

  def announce_next_turn(%__MODULE__{} = state) do
    round_info = Turns.round_info(state.game_id)
    text = MessageTemplates.next_turn(state, round_info)
    PubSub.msg(:spitegear, text)
    state
  end

  @reminder_interval_seconds 3 * 60 * 60

  @doc """
  Sends a kind reminder to the active player if a reminder is due, then
  persists the updated reminder state on `current_turn`.

  A reminder is due when both hold:
  - `reminded` was set more than 3 hours ago.
  - The current time falls within waking hours in America/Chicago (07:00–23:59).

  No-op when `current_turn` or `current_view_screen` is `nil`, or when
  `current_turn.reminded_at` is `nil`.
  """
  @spec send_reminder(t()) :: t()
  def send_reminder(%__MODULE__{history_changed: true} = state), do: state
  def send_reminder(%__MODULE__{current_turn: nil} = state), do: state
  def send_reminder(%__MODULE__{current_view_screen: nil} = state), do: state

  def send_reminder(%__MODULE__{} = state) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    if reminder_due?(state.current_turn, now) do
      vs = state.current_view_screen
      player_slack = vs.current_player && vs.current_player.slack_name
      text = MessageTemplates.kind_reminder(state.current_turn, player_slack, vs.game_name)
      PubSub.msg(:spitegear, text)
      {:ok, updated_turn} = Turns.record_reminder(state.current_turn)
      %{state | current_turn: updated_turn}
    else
      state
    end
  end

  defp reminder_due?(%{reminded_at: nil}, _now), do: false

  defp reminder_due?(%{reminded_at: reminded_at}, now) do
    {:ok, chicago} = DateTime.shift_zone(now, "America/Chicago")
    waking_hours? = chicago.hour >= 7 and chicago.hour < 24
    beyond_horizon? = DateTime.diff(now, reminded_at) > @reminder_interval_seconds
    waking_hours? and beyond_horizon?
  end

  @doc """
  Announces that the active player is taking their turn when history just
  changed, the current player matches the open turn, and at least one
  reminder has been sent. Persists `moving_announced: true` on the turn.

  No-op when `history_changed` is `false`, `current_turn` or
  `current_view_screen` is `nil`, or `current_turn.moving_announced` is
  already `true`.
  """
  @spec announce_moving(t()) :: t()
  def announce_moving(%__MODULE__{history_changed: false} = state), do: state
  def announce_moving(%__MODULE__{current_turn: nil} = state), do: state
  def announce_moving(%__MODULE__{current_view_screen: nil} = state), do: state
  def announce_moving(%__MODULE__{current_turn: %Turn{moving_announced: true}} = state), do: state

  def announce_moving(%__MODULE__{} = state) do
    vs = state.current_view_screen
    turn = state.current_turn
    same_player? = vs.current_player_name != nil && vs.current_player_name == turn.player_name

    if same_player? && turn.reminders >= 1 do
      Logger.info("#{turn.player_name} is taking their turn (game #{state.game_id})")
      text = MessageTemplates.player_moving(vs.current_player, state.game_id)
      PubSub.msg(:spitegear, text)
      {:ok, updated_turn} = Turns.record_moving_announced(turn)
      %{state | current_turn: updated_turn}
    else
      state
    end
  end

  @doc """
  Infers player deaths from skipped positions in turn order when a turn just
  advanced. Compares the player who just finished (`prev_turn.player_name`)
  to the player now active (`current_view_screen.current_player_name`). Any
  alive players between them in circular order are presumed eliminated.

  Only runs for fogged games — when the board is visible, `detect_eliminations/1`
  reads eliminations directly from the view screen instead.

  Persists each inferred death via `GameDeaths.create/3` and posts to
  `:spitegear_test`.

  No-op when `turn_advanced` is `false`, the game is not fogged, or
  `prev_turn` / `current_view_screen` is `nil`.
  """
  @spec infer_deaths_from_skip(t()) :: t()
  def infer_deaths_from_skip(%__MODULE__{turn_advanced: false} = state), do: state
  def infer_deaths_from_skip(%__MODULE__{prev_turn: nil} = state), do: state
  def infer_deaths_from_skip(%__MODULE__{current_view_screen: nil} = state), do: state

  def infer_deaths_from_skip(
        %__MODULE__{current_view_screen: %ViewScreen{fogged?: false}} = state
      ),
      do: state

  def infer_deaths_from_skip(%__MODULE__{} = state) do
    vs = state.current_view_screen
    prev_name = state.prev_turn.player_name
    curr_name = vs.current_player_name

    known_dead = GameDeaths.list(state.game_id) |> MapSet.new(& &1.player_name)

    alive_players =
      Enum.reject(vs.players, fn p ->
        p.eliminated? or p.winner? or MapSet.member?(known_dead, p.name)
      end)

    n = length(alive_players)
    prev_idx = Enum.find_index(alive_players, &(&1.name == prev_name))
    curr_idx = Enum.find_index(alive_players, &(&1.name == curr_name))
    newly_dead = do_skipped_players(alive_players, n, prev_idx, curr_idx)

    Enum.each(newly_dead, fn player ->
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      Logger.info("#{__MODULE__} inferring #{player.name} dead (skipped in turn order)")
      GameDeaths.create(state.game_id, player.name, now, inferred: true)
      text = MessageTemplates.player_died(player, state.game_id, vs.game_name)
      PubSub.msg(:spitegear_test, text)
    end)

    state
  end

  @doc """
  Detects newly eliminated players by diffing `current_view_screen.eliminated`
  against the persisted `game_deaths` records. Persists each new death via
  `GameDeaths.create/3` and posts to `:spitegear_test`.

  Only runs for unfogged games — when the board is fogged, eliminations are
  not reliably visible in the view screen and `infer_deaths_from_skip/1`
  handles detection instead.

  No-op when `view_screen_changed` is `false`, the game is fogged, or
  `current_view_screen` is `nil`.
  """
  @spec detect_eliminations(t()) :: t()
  def detect_eliminations(%__MODULE__{view_screen_changed: false} = state), do: state
  def detect_eliminations(%__MODULE__{current_view_screen: nil} = state), do: state

  def detect_eliminations(%__MODULE__{current_view_screen: %ViewScreen{fogged?: true}} = state),
    do: state

  def detect_eliminations(%__MODULE__{} = state) do
    vs = state.current_view_screen
    known_dead = GameDeaths.list(state.game_id) |> MapSet.new(& &1.player_name)
    newly_dead = Enum.reject(vs.eliminated, &MapSet.member?(known_dead, &1.name))

    Enum.each(newly_dead, fn player ->
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      GameDeaths.create(state.game_id, player.name, now)
      text = MessageTemplates.player_died(player, state.game_id, vs.game_name)
      PubSub.msg(:spitegear, text)
    end)

    state
  end

  @doc """
  Announces game winners and signals the calling GenServer to finish when
  `current_view_screen.winners` is non-empty.

  Publishes the winner blocks to `:spitegear` and sends
  `GenServer.cast(self(), :finish_game)` so the poller can capture the log
  snapshot and stop cleanly.

  No-op when `view_screen_changed` is `false`, `current_view_screen` is `nil`,
  or `winners` is empty.
  """
  @spec announce_winners(t()) :: t()
  def announce_winners(%__MODULE__{view_screen_changed: false} = state), do: state
  def announce_winners(%__MODULE__{current_view_screen: nil} = state), do: state

  def announce_winners(%__MODULE__{current_view_screen: %ViewScreen{winners: []}} = state),
    do: state

  def announce_winners(%__MODULE__{} = state) do
    vs = state.current_view_screen

    {blocks, fallback} =
      MessageTemplates.game_winners_blocks(vs.winners, state.game_id, vs.game_name)

    PubSub.msg(:spitegear, type: :game_winners, payload: {blocks, fallback})
    GenServer.cast(self(), :finish_game)
    state
  end

  defp do_skipped_players(_players, n, prev_idx, curr_idx)
       when is_nil(prev_idx) or is_nil(curr_idx) or n < 2,
       do: []

  defp do_skipped_players(players, n, prev_idx, curr_idx) do
    Stream.iterate(rem(prev_idx + 1, n), &rem(&1 + 1, n))
    |> Enum.take_while(&(&1 != curr_idx))
    |> Enum.map(&Enum.at(players, &1))
  end
end
