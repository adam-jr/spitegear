defmodule Spitegear.LiveGameState do
  @moduledoc """
  Struct representing the known live state of a single active game.

  Tracks the current and previous turns, view screen snapshots, and history
  API responses as persisted DB records. All fields are loaded from the
  database — they reflect what has already been written, not raw API responses.

  Use `new/1` to build an initial struct for a game, or `hydrate/1` to
  refresh an existing struct's fields (e.g. after restart).

  Use `dispatch_history_response/2` to process incoming history API data.

  For view screen updates, call the five pipeline steps in order:

      state
      |> LiveGameState.record_changed_view_screen_db(view_screen)
      |> LiveGameState.replace_current_view_screen()
      |> LiveGameState.advance_turn()
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
          last_round: non_neg_integer(),
          incoming_view_screen: WargearViewScreenDb.t() | nil,
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
            last_round: 0,
            incoming_view_screen: nil,
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
  Preserves transient dispatch flags (`view_screen_changed`, `turn_advanced`,
  `incoming_view_screen`).

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
        last_round: Turns.completed_rounds(game_id)
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

  Sets `incoming_view_screen` to the newly-inserted `WargearViewScreenDb`
  record and `view_screen_changed: true` when a change is detected. Sets both
  to their zero values when the screen is unchanged or the insert fails.

  Always follow this with `replace_current_view_screen/1`.
  """
  @spec record_changed_view_screen_db(t(), HTTPViewScreen.t()) :: t()
  def record_changed_view_screen_db(%__MODULE__{} = state, %HTTPViewScreen{} = view_screen) do
    case ViewScreens.record_if_changed(view_screen) do
      {:ok, :unchanged} ->
        %{state | incoming_view_screen: nil, view_screen_changed: false}

      {:ok, snapshot} ->
        %{state | incoming_view_screen: snapshot, view_screen_changed: true}

      {:error, _} ->
        Logger.error("#{__MODULE__} failed to record view screen for game #{state.game_id}")
        %{state | incoming_view_screen: nil, view_screen_changed: false}
    end
  end

  @doc """
  Swaps `current_view_screen` ← `incoming_view_screen` and shifts the
  previous `current_view_screen` into `prev_view_screen`. Clears
  `incoming_view_screen` after the swap.

  No-op when `view_screen_changed` is `false`.
  """
  @spec replace_current_view_screen(t()) :: t()
  def replace_current_view_screen(%__MODULE__{view_screen_changed: false} = state), do: state

  def replace_current_view_screen(%__MODULE__{incoming_view_screen: snapshot} = state) do
    %{
      state
      | prev_view_screen: state.current_view_screen,
        current_view_screen: snapshot,
        incoming_view_screen: nil
    }
  end

  @doc """
  Records a new turn start when the active player in `current_view_screen`
  differs from the player in `current_turn`.

  On a player change, closes the open turn, inserts a new one via
  `Turns.record_turn_start/2`, shifts `current_turn` → `prev_turn` (with
  `ended_at` set to the new turn's `started_at`), and sets
  `turn_advanced: true`.

  No-op — setting `turn_advanced: false` — when the view screen was unchanged,
  `current_view_screen` is nil, or the active player is the same.
  """
  @spec advance_turn(t()) :: t()
  def advance_turn(%__MODULE__{view_screen_changed: false} = state),
    do: %{state | turn_advanced: false}

  def advance_turn(%__MODULE__{current_view_screen: nil} = state),
    do: %{state | turn_advanced: false}

  def advance_turn(%__MODULE__{} = state) do
    new_player = state.current_view_screen.current_player_name
    current = state.current_turn && state.current_turn.player_name

    if current == new_player do
      %{state | turn_advanced: false}
    else
      case Turns.record_turn_start(state.game_id, new_player) do
        {:ok, new_turn} ->
          closed_prev =
            state.current_turn && %{state.current_turn | ended_at: new_turn.started_at}

          %{state | prev_turn: closed_prev, current_turn: new_turn, turn_advanced: true}

        {:error, _} ->
          Logger.error("#{__MODULE__} failed to advance turn for game #{state.game_id}")
          %{state | turn_advanced: false}
      end
    end
  end

  @doc """
  Publishes a round-complete message to `:spitegear_test` when
  `Turns.completed_rounds/1` exceeds `last_round`. Updates `last_round` on
  the struct.

  No-op when `turn_advanced` is `false`.
  """
  @spec announce_next_round(t()) :: t()
  def announce_next_round(%__MODULE__{turn_advanced: false} = state), do: state

  def announce_next_round(%__MODULE__{} = state) do
    rounds = Turns.completed_rounds(state.game_id)

    if rounds > state.last_round do
      PubSub.msg(:spitegear_test, "Round #{rounds} complete in game #{state.game_id}")
      %{state | last_round: rounds}
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
