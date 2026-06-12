defmodule Spitegear.Worker.GamePoller do
  @moduledoc false
  use GenServer

  alias Spitegear.Wargear.HTTP.History
  alias Spitegear.Wargear.HTTP.ViewScreen
  alias Spitegear.Worker.GameManager

  require Logger

  @interval :timer.seconds(20)
  @view_screen_interval :timer.minutes(1)
  @view_screen_max_polls 10

  @state %{
    game_id: nil,
    last_turn_id: nil,
    view_screen_timer: nil,
    view_screen_polls_remaining: 0
  }

  def child_spec(game_id: game_id) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [[game_id: game_id, name: :"#{__MODULE__}_#{game_id}"]]},
      type: :worker,
      restart: :temporary
    }
  end

  def start_link(game_id: game_id, name: name) do
    GenServer.start_link(__MODULE__, [game_id: game_id], name: name)
  end

  @impl true
  def init(game_id: game_id) do
    Logger.info("Initializing #{__MODULE__} with game_id #{game_id}")
    Logger.info("#{__MODULE__} will poll wargear.net every #{@interval / 1000} second(s)")

    send(self(), :update_game)
    schedule_work()

    {:ok, %{@state | game_id: game_id}}
  end

  @impl true
  def handle_info(:work, %{game_id: game_id, last_turn_id: nil} = state) do
    case History.latest_turn(game_id) do
      {:ok, %{"turnid" => turn_id} = turn_data} ->
        GameManager.notify_history_fetched(game_id, turn_data)
        schedule_work()
        {:noreply, %{state | last_turn_id: turn_id}}

      _ ->
        schedule_work()
        {:noreply, state}
    end
  end

  def handle_info(:work, %{game_id: game_id, last_turn_id: last_turn_id} = state) do
    case History.latest_turn(game_id) do
      {:ok, %{"turnid" => ^last_turn_id} = turn_data} ->
        GameManager.notify_history_fetched(game_id, turn_data)
        schedule_work()
        {:noreply, state}

      {:ok, %{"turnid" => turn_id} = turn_data} ->
        GameManager.notify_history_fetched(game_id, turn_data)
        if state.view_screen_timer, do: Process.cancel_timer(state.view_screen_timer)

        state = %{
          state
          | last_turn_id: turn_id,
            view_screen_timer: nil,
            view_screen_polls_remaining: @view_screen_max_polls
        }

        case fetch_view_screen(state) do
          {:stop, state} ->
            {:stop, :normal, state}

          {:continue, state} ->
            schedule_work()
            {:noreply, state}
        end

      _ ->
        schedule_work()
        {:noreply, state}
    end
  end

  def handle_info(:poll_view_screen, state) do
    case fetch_view_screen(state) do
      {:stop, state} -> {:stop, :normal, state}
      {:continue, state} -> {:noreply, state}
    end
  end

  def handle_info(:update_game, state) do
    case ViewScreen.get_game(state.game_id) do
      {:ok, view_screen} ->
        GameManager.notify_view_screen_fetched(state.game_id, view_screen)
        {:noreply, state}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:ssl_closed, _}, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(:normal, %{game_id: game_id}) do
    GameManager.stop(game_id)
  end

  def terminate(_reason, _state), do: :ok

  def name(game_id), do: :"#{__MODULE__}_#{game_id}"

  defp fetch_view_screen(state) do
    polls_remaining = state.view_screen_polls_remaining - 1

    case ViewScreen.get_game(state.game_id) do
      {:ok, view_screen} ->
        GameManager.notify_view_screen_fetched(state.game_id, view_screen)
        state = %{state | view_screen_polls_remaining: polls_remaining}

        if Enum.any?(view_screen.winners) do
          {:stop, state}
        else
          {timer, remaining} = maybe_schedule_view_screen_poll(polls_remaining)
          {:continue, %{state | view_screen_timer: timer, view_screen_polls_remaining: remaining}}
        end

      error ->
        Logger.error(
          "#{__MODULE__} ViewScreen.get_game failed for game #{state.game_id}: #{inspect(error)}"
        )

        {timer, remaining} = maybe_schedule_view_screen_poll(polls_remaining)
        {:continue, %{state | view_screen_timer: timer, view_screen_polls_remaining: remaining}}
    end
  end

  defp maybe_schedule_view_screen_poll(remaining) when remaining > 0 do
    {Process.send_after(self(), :poll_view_screen, @view_screen_interval), remaining}
  end

  defp maybe_schedule_view_screen_poll(_), do: {nil, 0}

  defp schedule_work, do: Process.send_after(self(), :work, @interval)
end
