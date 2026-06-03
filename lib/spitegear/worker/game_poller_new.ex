defmodule Spitegear.Worker.GamePollerNew do
  @moduledoc false
  use GenServer

  alias Spitegear.PubSub
  alias Spitegear.Wargear.HTTP.History

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

  @doc "Returns the registered name for the poller for `game_id`."
  def name(game_id), do: :"#{__MODULE__}_#{game_id}"

  @doc "Returns `true` if a poller is running for `game_id`."
  def alive?(game_id), do: Process.whereis(name(game_id)) != nil

  def init(game_id: game_id) do
    Logger.info("#{__MODULE__} starting for game #{game_id}")
    schedule_work()
    {:ok, %{game_id: game_id, last_turn_id: nil}}
  end

  def handle_info(:work, %{game_id: game_id, last_turn_id: nil} = state) do
    case History.latest_turn(game_id) do
      {:ok, %{"turnid" => turn_id}} ->
        schedule_work()
        {:noreply, %{state | last_turn_id: turn_id}}

      _ ->
        schedule_work()
        {:noreply, state}
    end
  end

  def handle_info(:work, %{game_id: game_id, last_turn_id: last_turn_id} = state) do
    case History.latest_turn(game_id) do
      {:ok, %{"turnid" => ^last_turn_id}} ->
        schedule_work()
        {:noreply, state}

      {:ok, %{"turnid" => turn_id}} ->
        Logger.info("#{__MODULE__} new activity on game #{game_id}: turn #{turn_id}")
        PubSub.msg(:spitegear_test, "new activity on game #{game_id} (turn #{turn_id})")
        schedule_work()
        {:noreply, %{state | last_turn_id: turn_id}}

      _ ->
        schedule_work()
        {:noreply, state}
    end
  end

  def handle_info({:ssl_closed, _}, state), do: {:noreply, state}

  defp schedule_work, do: Process.send_after(self(), :work, @interval)
end
