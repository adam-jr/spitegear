defmodule Spitegear.Worker.GamePollerNew do
  @moduledoc """
  Experimental replacement for `GamePoller`.

  One `GamePollerNew` GenServer runs per active game. Every
  #{div(:timer.seconds(20), 1000)} seconds it asks `LiveGameState` to fetch
  the latest turn from wargear.net and checks whether the result has changed.
  On new activity it posts a notification to the `spitegear_test` Slack
  channel.

  All HTTP logic and state comparison live in `LiveGameState`. This module's
  only job is to drive the polling loop.

  Start and stop a poller for any running game from the admin:

      Games.start_new_poller(game_id)
      Games.stop_new_poller(game_id)
  """

  use GenServer

  alias Spitegear.LiveGameState
  alias Spitegear.PubSub

  require Logger

  @interval :timer.seconds(20)

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

  def init(game_id: game_id) do
    Logger.info("#{__MODULE__} starting for game #{game_id}")
    schedule_next_turn_check()
    {:ok, %{game_id: game_id, game_state: LiveGameState.new(game_id)}}
  end

  def handle_info(:fetch_latest_turn, %{game_state: game_state} = state) do
    game_state = LiveGameState.fetch_game_state(game_state)

    if LiveGameState.new_activity?(game_state) do
      PubSub.msg(:spitegear_test, "new activity on game #{game_state.game_id}")
    end

    schedule_next_turn_check()
    {:noreply, %{state | game_state: game_state}}
  end

  def handle_info({:ssl_closed, _}, state), do: {:noreply, state}

  defp schedule_next_turn_check,
    do: Process.send_after(self(), :fetch_latest_turn, @interval)
end
