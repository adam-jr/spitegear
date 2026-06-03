defmodule Spitegear.Worker.GamePollerNew do
  @moduledoc """
  Experimental replacement for `GamePoller`.

  One `GamePollerNew` GenServer runs per active game. Rather than polling
  wargear.net directly, it receives notifications from `GamePoller` whenever
  that poller successfully fetches a `History.latest_turn` or `ViewScreen`.

  Start and stop a poller for any running game from the admin:

      Games.start_new_poller(game_id)
      Games.stop_new_poller(game_id)
  """

  use GenServer

  alias Spitegear.LiveGameState.HistoryResponses
  alias Spitegear.LiveGameState.ViewScreens

  require Logger

  def child_spec(game_id: game_id) do
    %{
      id: {__MODULE__, game_id},
      start: {__MODULE__, :start_link, [[game_id: game_id, name: name(game_id)]]},
      type: :worker,
      restart: :temporary
    }
  end

  def start_link(game_id: game_id, name: name) do
    GenServer.start_link(__MODULE__, [game_id: game_id], name: name)
  end

  @doc "Returns the registered process name for `game_id`."
  @spec name(String.t()) :: atom()
  def name(game_id), do: :"#{__MODULE__}_#{game_id}"

  @doc "Returns `true` if a `GamePollerNew` is currently running for `game_id`."
  @spec alive?(String.t()) :: boolean()
  def alive?(game_id), do: Process.whereis(name(game_id)) != nil

  @doc "Notifies the new poller of a successful `History.latest_turn` fetch. No-op if not running."
  @spec notify_history_fetched(String.t(), map()) :: :ok
  def notify_history_fetched(game_id, turn_data) do
    if alive?(game_id), do: GenServer.cast(name(game_id), {:history_fetched, turn_data})
    :ok
  end

  @doc "Notifies the new poller of a successful `ViewScreen.get_game` fetch. No-op if not running."
  @spec notify_view_screen_fetched(String.t(), term()) :: :ok
  def notify_view_screen_fetched(game_id, view_screen) do
    if alive?(game_id), do: GenServer.cast(name(game_id), {:view_screen_fetched, view_screen})
    :ok
  end

  @impl true
  def init(game_id: game_id) do
    Logger.info("#{__MODULE__} starting for game #{game_id}")
    {:ok, %{game_id: game_id}}
  end

  @impl true
  def handle_cast({:history_fetched, turn_data}, state) do
    HistoryResponses.record_if_changed(state.game_id, turn_data)
    {:noreply, state}
  end

  def handle_cast({:view_screen_fetched, view_screen}, state) do
    ViewScreens.record_if_changed(view_screen)
    {:noreply, state}
  end

  @impl true
  def handle_info({:ssl_closed, _}, state), do: {:noreply, state}
end
