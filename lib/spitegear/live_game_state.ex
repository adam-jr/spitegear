defmodule Spitegear.LiveGameState do
  @moduledoc """
  Struct representing the known live state of a single active game.

  Tracks the current and previous turns, view screen snapshots, and history
  API responses as persisted DB records. All fields are loaded from the
  database — they reflect what has already been written, not raw API responses.

  Use `new/1` to build an initial struct for a game, or `hydrate/1` to
  refresh an existing struct's fields (e.g. after restart).

  Use `dispatch_history_response/2` and `dispatch_view_screen/2` to process incoming
  data from the legacy poller. Each function checks whether the incoming data
  represents a change, persists it if so, and returns an updated struct with
  the current/prev fields shifted in-memory — no extra DB read needed.
  """

  alias Spitegear.LiveGameState.HistoryResponses
  alias Spitegear.LiveGameState.Turn
  alias Spitegear.LiveGameState.Turns
  alias Spitegear.LiveGameState.ViewScreens
  alias Spitegear.LiveGameState.WargearHistoryApiResponseDb
  alias Spitegear.LiveGameState.WargearViewScreenDb
  alias Spitegear.Wargear.HTTP.ViewScreen, as: RawViewScreen

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
  def new(game_id), do: hydrate(%__MODULE__{game_id: game_id})

  @doc """
  Hydrates all DB-backed fields on the given struct from the database.
  Preserves all other fields on `state`.

  Loads the open/last-closed turn, two most recent view screen snapshots,
  and two most recent history API responses.

  Call this on startup or after a crash restart. For ongoing updates, prefer
  `dispatch_history_response/2` and `dispatch_view_screen/2`, which update the
  struct in-memory without an extra DB read.
  """
  @spec hydrate(t()) :: t()
  def hydrate(%__MODULE__{game_id: game_id} = state) do
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

  @doc """
  Processes a raw History API response. Persists it if the `turnid` has
  changed, then shifts `current_history_response` → `prev_history_response`
  and sets `current_history_response` to the new record.

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
          | prev_history_response: state.current_history_response,
            current_history_response: record
        }

      {:error, _} ->
        state
    end
  end

  @doc """
  Processes a raw ViewScreen. Persists it if any tracked field has changed,
  shifts `current_view_screen` → `prev_view_screen`, and sets
  `current_view_screen` to the new snapshot.

  Also detects turn changes: if the active player in the incoming ViewScreen
  differs from `current_turn.player_name`, records the turn transition via
  `Turns.record_turn_start/2` and shifts `current_turn` → `prev_turn`
  in-memory.

  Returns the struct unchanged if the view screen and active player are both
  identical to the last stored state, or if any write fails.
  """
  @spec dispatch_view_screen(t(), RawViewScreen.t()) :: t()
  def dispatch_view_screen(%__MODULE__{} = state, raw) do
    state =
      case ViewScreens.record_if_changed(raw) do
        {:ok, :unchanged} ->
          state

        {:ok, snapshot} ->
          %{state | prev_view_screen: state.current_view_screen, current_view_screen: snapshot}

        {:error, _} ->
          state
      end

    incoming_player = raw.current_player && raw.current_player.name
    maybe_record_turn_start(state, incoming_player)
  end

  defp maybe_record_turn_start(state, nil), do: state

  defp maybe_record_turn_start(%__MODULE__{} = state, new_player) do
    current = state.current_turn && state.current_turn.player_name

    if current == new_player do
      state
    else
      case Turns.record_turn_start(state.game_id, new_player) do
        {:ok, new_turn} ->
          closed_prev =
            state.current_turn && %{state.current_turn | ended_at: new_turn.started_at}

          %{state | prev_turn: closed_prev, current_turn: new_turn}

        {:error, _} ->
          state
      end
    end
  end
end
