defmodule Spitegear.LiveGameState do
  @moduledoc """
  Struct representing the known live state of a single active game.

  Tracks the current and previous turns, view screen snapshots, and history
  API responses as persisted DB records. All fields are loaded from the
  database — they reflect what has already been written, not raw API responses.

  Use `new/1` to build an initial struct for a game, or `hydrate/1` to
  refresh an existing struct's fields (e.g. after restart).

  Use `dispatch_history_response/2` to process incoming history API data.

  For view screen updates, call the pipeline steps in order:

      state
      |> LiveGameState.record_changed_view_screen_db(view_screen)
      |> LiveGameState.advance_turn()
      |> LiveGameState.fetch_log_if_unfogged()
      |> LiveGameState.announce_next_round()
      |> LiveGameState.announce_next_turn()

  Each step is a no-op when its precondition is not met, so the pipeline
  always returns a valid struct.
  """

  require Logger

  alias Spitegear.LiveGameState.HistoryResponses
  alias Spitegear.LiveGameState.Turn
  alias Spitegear.LiveGameState.Turns
  alias Spitegear.LiveGameState.ViewScreens
  alias Spitegear.LiveGameState.WargearHistoryApiResponseDb
  alias Spitegear.LiveGameState.WargearViewScreenDb
  alias Spitegear.PubSub
  alias Spitegear.Wargear.HTTP.ViewScreen, as: HTTPViewScreen

  @type t :: %__MODULE__{
          game_id: String.t() | nil,
          current_turn: Turn.t() | nil,
          prev_turn: Turn.t() | nil,
          current_view_screen: WargearViewScreenDb.t() | nil,
          prev_view_screen: WargearViewScreenDb.t() | nil,
          current_api_response: WargearHistoryApiResponseDb.t() | nil,
          prev_api_response: WargearHistoryApiResponseDb.t() | nil,
          completed_round: non_neg_integer(),
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
            completed_round: 0,
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
  Loads turns, view screen snapshots, history responses, and `completed_round`.
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
        prev_api_response: HistoryResponses.get_prev(game_id),
        completed_round: Turns.completed_rounds(game_id)
    }
  end

  @doc """
  Processes a raw History API response. Persists it if the `turnid` has
  changed, then shifts `current_api_response` → `prev_api_response`
  and sets `current_api_response` to the new record.

  Returns the struct unchanged if the response is identical to the last stored
  one or if the insert fails.
  """
  @spec dispatch_history_response(t(), map()) :: t()
  def dispatch_history_response(%__MODULE__{} = state, turn_data) do
    case HistoryResponses.record_if_changed(state.game_id, turn_data) do
      {:ok, :unchanged} ->
        state

      {:ok, record} ->
        %{
          state
          | prev_api_response: state.current_api_response,
            current_api_response: record
        }

      {:error, _} ->
        Logger.error("#{__MODULE__} failed to record history response for game #{state.game_id}")
        state
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

  def advance_turn(
        %__MODULE__{
          current_view_screen: %WargearViewScreenDb{current_player_name: player_name},
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
  def fetch_log_if_unfogged(%__MODULE__{current_view_screen: %{fogged: true}} = state), do: state

  def fetch_log_if_unfogged(%__MODULE__{} = state) do
    GenServer.cast(self(), :fetch_log)
    state
  end

  @doc """
  Queries `Turns.completed_rounds/1` and, when the result exceeds
  `completed_round`, publishes a round-complete message to `:spitegear_test` and
  updates `completed_round` on the struct.

  This is the only pipeline step that reads from the database.

  No-op when `turn_advanced` is `false`.
  """
  @spec announce_next_round(t()) :: t()
  def announce_next_round(%__MODULE__{turn_advanced: false} = state), do: state

  def announce_next_round(%__MODULE__{} = state) do
    rounds = Turns.completed_rounds(state.game_id)

    if rounds > state.completed_round do
      PubSub.msg(:spitegear_test, "Round #{rounds} complete in game #{state.game_id}")
      %{state | completed_round: rounds}
    else
      state
    end
  end

  @doc """
  Publishes a next-turn message for `current_turn.player_name` to
  `:spitegear_test`.

  No-op when `turn_advanced` is `false` or `current_turn` is `nil`.
  """
  @spec announce_next_turn(t()) :: t()
  def announce_next_turn(%__MODULE__{turn_advanced: false} = state), do: state
  def announce_next_turn(%__MODULE__{current_turn: nil} = state), do: state

  def announce_next_turn(%__MODULE__{} = state) do
    PubSub.msg(
      :spitegear_test,
      "#{state.current_turn.player_name}'s turn in game #{state.game_id}"
    )

    state
  end
end
