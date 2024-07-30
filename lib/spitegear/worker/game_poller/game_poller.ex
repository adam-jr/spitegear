defmodule Spitegear.Worker.GamePoller do
  use GenServer

  alias Spitegear.HTML.ViewScreen
  alias __MODULE__.Turn

  require Logger

  @interval :timer.seconds(20)

  @state %{
    game_id: nil,
    view_screen: nil,
    dead_players: [],
    current_turn: nil,
    status: :players_joining
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

    update_spreadsheet()
    schedule_work()

    {:ok, %{@state | game_id: game_id}}
  end

  def handle_info(:work, %{game_id: game_id} = state) do
    case ViewScreen.get_game(game_id) do
      {:ok, view_screen} ->
        state =
          %{state | view_screen: view_screen}
          |> update_status()
          |> update_turn()
          |> update_eliminated()
          |> maybe_announce_winners()

        if Enum.any?(view_screen.winners) do
          update_spreadsheet()
          finish_game(game_id)
          {:stop, :normal, nil}
        else
          schedule_work()
          {:noreply, state}
        end

      _ ->
        schedule_work()
        {:noreply, state}
    end
  end

  def handle_info(:update_spreadsheet, state) do
    case ViewScreen.get_game(state.game_id) do
      {:ok, view_screen} ->
        Spitegear.GoogleSpreadsheets.Sheets.Games.update_or_create_row(view_screen)

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:ssl_closed, _}, state) do
    {:noreply, state}
  end

  def update_status(state) do
    if state.view_screen.current_player do
      %{state | status: :in_progress}
    else
      state
    end
  end

  def update_turn(%{status: s} = state) when s != :in_progress, do: state

  def update_turn(state) do
    if new_turn?(state) do
      player = state.view_screen.current_player
      Logger.info("Notifying #{player.name} of turn...")
      Spitegear.PubSub.msg(:spitegear, type: :next_turn, payload: {player, state.game_id})

      %{
        state
        | current_turn: %Turn{
            game_id: state.game_id,
            player: player,
            reminded_at: DateTime.utc_now()
          }
      }
    else
      state
    end
  end

  def update_eliminated(state) do
    last_eliminated = Enum.map(state.dead_players, & &1.name)
    newly_eliminated = state.view_screen.eliminated

    case Enum.reject(newly_eliminated, &(&1.name in last_eliminated)) do
      [] ->
        state

      newly_dead ->
        Enum.each(newly_dead, fn player ->
          text = Spitegear.Slack.Message.text(:player_died, player, state.game_id)
          Spitegear.PubSub.msg(:spitegear_test, text)
        end)

        %{state | dead_players: state.view_screen.eliminated}
    end
  end

  def maybe_announce_winners(state) do
    if Enum.any?(state.view_screen.winners) do
      text = Spitegear.Slack.Message.text(:game_winners, state.view_screen.winners, state.game_id)
      Spitegear.PubSub.msg(:spitegear_test, text)
      Spitegear.PubSub.msg(:spitegear_test, text)
      Spitegear.PubSub.msg(:spitegear_test, text)
    end

    state
  end

  defp update_spreadsheet do
    send(self(), :update_spreadsheet)
  end

  defp finish_game(_game_id) do
    # update google sheet w/ winners and date etc
  end

  defp schedule_work, do: Process.send_after(self(), :work, @interval)

  defp new_turn?(%{current_turn: %{player: %{name: name}}, view_screen: view_screen}) do
    name != view_screen.current_player.name
  end

  defp new_turn?(%{view_screen: view_screen}) do
    view_screen.current_player != nil
  end
end
