defmodule Spitegear.Worker.GamePoller do
  @moduledoc false
  use GenServer

  alias Spitegear.Games
  alias Spitegear.Turn
  alias Spitegear.Wargear.HTTP.History
  alias Spitegear.Wargear.HTTP.ViewScreen
  alias Spitegear.Worker.GamePoller.TurnLogic
  alias Spitegear.Worker.GamePollerNew

  require Logger

  @interval :timer.seconds(20)
  @view_screen_interval :timer.minutes(1)
  @view_screen_max_polls 10

  @state %{
    game_id: nil,
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

    update_game()
    update_current_turn()
    schedule_work()

    dead_players = Games.list_deaths(game_id) |> Enum.map(&%{name: &1.player_name})

    {:ok,
     %{
       @state
       | game_id: game_id,
         last_round: Games.completed_rounds(game_id),
         dead_players: dead_players
     }}
  end

  @impl true
  def handle_info(:work, %{game_id: game_id, last_turn_id: nil} = state) do
    case History.latest_turn(game_id) do
      {:ok, %{"turnid" => turn_id} = turn_data} ->
        GamePollerNew.notify_history_fetched(game_id, turn_data)
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
        GamePollerNew.notify_history_fetched(game_id, turn_data)
        schedule_work()
        {:noreply, state}

      {:ok, %{"turnid" => turn_id} = turn_data} ->
        GamePollerNew.notify_history_fetched(game_id, turn_data)
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
        Games.upsert_game(view_screen)
        GamePollerNew.notify_view_screen_fetched(state.game_id, view_screen)
        {:noreply, update_status(%{state | view_screen: view_screen})}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info(:update_current_turn, state) do
    turn = Games.get_current_turn(state.game_id)
    moving_announced = if turn, do: turn.moving_announced, else: false
    {:noreply, %{state | current_turn: turn, moving_announced: moving_announced}}
  end

  def handle_info({:ssl_closed, _}, state) do
    {:noreply, state}
  end

  def name(game_id), do: :"#{__MODULE__}_#{game_id}"

  def update_current_turn, do: send(self(), :update_current_turn)

  def update_status(state) do
    if state.view_screen.current_player do
      %{state | status: :in_progress}
    else
      state
    end
  end

  defp fetch_view_screen(state) do
    polls_remaining = state.view_screen_polls_remaining - 1

    case ViewScreen.get_game(state.game_id) do
      {:ok, view_screen} ->
        GamePollerNew.notify_view_screen_fetched(state.game_id, view_screen)

        state =
          %{state | view_screen: view_screen, view_screen_polls_remaining: polls_remaining}
          |> update_status()
          |> update_turn()

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

  defp update_turn(%{status: s} = state) when s != :in_progress, do: state

  defp update_turn(state) do
    if TurnLogic.new_turn?(state), do: new_turn(state), else: state
  end

  defp new_turn(state) do
    state = record_completed_turn(state)

    turn = %Turn{
      game_id: state.game_id,
      player: state.view_screen.current_player,
      started: DateTime.utc_now() |> DateTime.truncate(:second),
      reminded: DateTime.utc_now() |> DateTime.truncate(:second),
      reminders: 0
    }

    Games.upsert_turn(turn)

    %{state | current_turn: turn, moving_announced: false}
  end

  defp record_completed_turn(%{current_turn: nil} = state), do: state

  defp record_completed_turn(state) do
    ended = DateTime.utc_now() |> DateTime.truncate(:second)
    Games.record_completed_turn(state.current_turn, ended)
    state
  end

  defp update_game, do: send(self(), :update_game)

  defp schedule_work, do: Process.send_after(self(), :work, @interval)
end
