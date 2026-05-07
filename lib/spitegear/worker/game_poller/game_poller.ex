defmodule Spitegear.Worker.GamePoller do
  use GenServer

  alias Spitegear.HTML.ViewScreen
  alias Spitegear.Wargear.History

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
    moving_announced: false
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

  def init(game_id: game_id) do
    Logger.info("Initializing #{__MODULE__} with game_id #{game_id}")
    Logger.info("#{__MODULE__} will poll wargear.net every #{@interval / 1000} second(s)")

    update_game()
    update_current_turn()
    schedule_work()

    {:ok, %{@state | game_id: game_id}}
  end

  def handle_info(:work, %{game_id: game_id, last_turn_id: last_turn_id} = state) do
    case History.latest_turn(game_id) do
      {:ok, %{"turnid" => ^last_turn_id}} ->
        state = maybe_remind(state)
        schedule_work()
        {:noreply, state}

      {:ok, %{"turnid" => turn_id}} ->
        if state.view_screen_timer, do: Process.cancel_timer(state.view_screen_timer)
        state = %{state | last_turn_id: turn_id, view_screen_timer: nil, view_screen_polls_remaining: @view_screen_max_polls}

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
        Spitegear.Games.upsert_game(view_screen)
        {:noreply, state}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info(:update_current_turn, state) do
    turn = Spitegear.Games.get_current_turn(state.game_id)
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
        state =
          %{state | view_screen: view_screen, view_screen_polls_remaining: polls_remaining}
          |> maybe_announce_moving()
          |> update_status()
          |> update_turn()
          |> update_eliminated()
          |> maybe_announce_winners()

        if Enum.any?(view_screen.winners) do
          update_game()
          finish_game(state.game_id)
          {:stop, state}
        else
          {timer, remaining} = maybe_schedule_view_screen_poll(polls_remaining)
          {:continue, %{state | view_screen_timer: timer, view_screen_polls_remaining: remaining}}
        end

      error ->
        Logger.error("#{__MODULE__} ViewScreen.get_game failed for game #{state.game_id}: #{inspect(error)}")
        {timer, remaining} = maybe_schedule_view_screen_poll(polls_remaining)
        {:continue, %{state | view_screen_timer: timer, view_screen_polls_remaining: remaining}}
    end
  end

  defp maybe_schedule_view_screen_poll(remaining) when remaining > 0 do
    {Process.send_after(self(), :poll_view_screen, @view_screen_interval), remaining}
  end

  defp maybe_schedule_view_screen_poll(_), do: {nil, 0}

  defp maybe_remind(%{status: s} = state) when s != :in_progress, do: state

  defp maybe_remind(state) do
    if reminder_due?(state), do: remind_player(state), else: state
  end

  defp update_turn(%{status: s} = state) when s != :in_progress, do: state

  defp update_turn(state) do
    cond do
      new_turn?(state) -> new_turn(state)
      reminder_due?(state) -> remind_player(state)
      true -> state
    end
  end

  # 3 hours
  @horizon_seconds 3 * 60 * 60
  defp reminder_due?(%{current_turn: %{reminded: reminded_time}}) do
    current_time_utc = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, current_time_chicago} = DateTime.shift_zone(current_time_utc, "America/Chicago")
    current_hour_chicago = current_time_chicago.hour
    waking_hours_chicago? = current_hour_chicago >= 7 and current_hour_chicago < 24

    beyond_horizon? = DateTime.diff(current_time_utc, reminded_time) > @horizon_seconds
    waking_hours_chicago? and beyond_horizon?
  end

  defp reminder_due?(_state), do: false

  defp remind_player(state) do
    player = state.current_turn.player
    Logger.info("Reminding #{player.name} of turn...")
    text = Spitegear.Slack.Message.text(:kind_reminder, state.current_turn)
    Spitegear.PubSub.msg(:spitegear, text)

    turn = %{
      state.current_turn
      | reminded: DateTime.utc_now() |> DateTime.truncate(:second),
        reminders: state.current_turn.reminders + 1
    }

    Spitegear.Games.upsert_turn(turn)

    %{state | current_turn: turn}
  end

  defp new_turn?(%{view_screen: %{current_player: nil}}), do: false

  defp new_turn?(%{current_turn: %{player: %{name: name}}, view_screen: view_screen}) do
    name != view_screen.current_player.name
  end

  defp new_turn?(%{view_screen: view_screen}) do
    view_screen.current_player != nil
  end

  defp new_turn(state) do
    player = state.view_screen.current_player
    Logger.info("Notifying #{player.name} of turn...")
    Spitegear.PubSub.msg(:spitegear, type: :next_turn, payload: {player, state.game_id})

    state = record_completed_turn(state)

    turn = %Spitegear.Turn{
      game_id: state.game_id,
      player: state.view_screen.current_player,
      started: DateTime.utc_now() |> DateTime.truncate(:second),
      reminded: DateTime.utc_now() |> DateTime.truncate(:second),
      reminders: 0
    }

    Spitegear.Games.upsert_turn(turn)

    %{state | current_turn: turn, moving_announced: false}
  end

  defp record_completed_turn(%{current_turn: nil} = state), do: state

  defp record_completed_turn(state) do
    ended = DateTime.utc_now() |> DateTime.truncate(:second)
    Spitegear.Games.record_completed_turn(state.current_turn, ended)

    active_players = length(state.view_screen.players) - length(state.view_screen.eliminated)
    round_size = active_players * 5

    if round_size > 0 do
      turn_count = Spitegear.Games.completed_turn_count(state.game_id)

      if rem(turn_count, round_size) == 0 do
        stats = Spitegear.Games.turn_stats(state.game_id)
        text = Spitegear.Slack.Message.text(:turn_stats, stats, state.game_id)
        Spitegear.PubSub.msg(:spitegear, text)
      end
    end

    state
  end

  defp maybe_announce_moving(%{current_turn: nil} = state), do: state
  defp maybe_announce_moving(%{moving_announced: true} = state), do: state

  defp maybe_announce_moving(state) do
    %{view_screen: view_screen, current_turn: current_turn} = state

    same_player? =
      view_screen.current_player != nil &&
        view_screen.current_player.name == current_turn.player.name

    if same_player? && current_turn.reminders >= 1 do
      Logger.info("#{current_turn.player.name} is taking their turn...")
      text = Spitegear.Slack.Message.text(:player_moving, current_turn.player)
      Spitegear.PubSub.msg(:spitegear, text)
      turn = %{current_turn | moving_announced: true}
      Spitegear.Games.upsert_turn(turn)
      %{state | moving_announced: true, current_turn: turn}
    else
      state
    end
  end

  defp update_game, do: send(self(), :update_game)

  defp finish_game(_game_id), do: :ok

  defp schedule_work, do: Process.send_after(self(), :work, @interval)

  defp update_eliminated(state) do
    last_eliminated = Enum.map(state.dead_players, & &1.name)
    newly_eliminated = state.view_screen.eliminated

    case Enum.reject(newly_eliminated, &(&1.name in last_eliminated)) do
      [] ->
        state

      newly_dead ->
        Enum.each(newly_dead, fn player ->
          text = Spitegear.Slack.Message.text(:player_died, player, state.game_id)
          Spitegear.PubSub.msg(:spitegear, text)
        end)

        %{state | dead_players: state.view_screen.eliminated}
    end
  end

  defp maybe_announce_winners(state) do
    if Enum.any?(state.view_screen.winners) do
      text = Spitegear.Slack.Message.text(:game_winners, state.view_screen.winners, state.game_id)
      Spitegear.PubSub.msg(:spitegear, text)
      Spitegear.PubSub.msg(:spitegear, text)
      Spitegear.PubSub.msg(:spitegear, text)
    end

    state
  end
end
