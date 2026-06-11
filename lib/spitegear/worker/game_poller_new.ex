defmodule Spitegear.Worker.GamePollerNew do
  @moduledoc """
  One GenServer per active game. Polls wargear.net directly and runs the
  `LiveGameState` pipeline on each result.

  Two-layer polling:

  - **History** (`/rest/GetHistoryUpdate/:id`) every 20 s — cheap, detects
    turn changes by comparing `turnid`.
  - **ViewScreen** (HTML scrape of `/games/view/:id`) — fetched once on
    startup, then a burst of up to 10 polls (1 min apart) after each new
    turn is detected.

  On game completion, `LiveGameState.announce_winners/1` casts `:finish_game`
  to this process, which captures the final log snapshot and stops normally.
  """

  use GenServer

  alias Spitegear.GameLog.Processor
  alias Spitegear.Games
  alias Spitegear.LiveGameState
  alias Spitegear.Wargear.HTTP.History
  alias Spitegear.Wargear.HTTP.LogSnapshot
  alias Spitegear.Wargear.HTTP.ViewScreen

  require Logger

  @history_interval :timer.seconds(20)
  @view_screen_interval :timer.minutes(1)
  @view_screen_max_polls 10

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

  @impl true
  def init(game_id: game_id) do
    Logger.info("#{__MODULE__} starting for game #{game_id}")

    {:ok,
     %{
       game_state: %LiveGameState{game_id: game_id},
       last_turn_id: nil,
       view_screen_polls_remaining: 0
     }, {:continue, :hydrate}}
  end

  @impl true
  def handle_continue(:hydrate, %{game_state: game_state} = state) do
    game_state = LiveGameState.hydrate(game_state)
    send(self(), :poll_history)
    send(self(), :poll_view_screen)
    {:noreply, %{state | game_state: game_state, view_screen_polls_remaining: 1}}
  end

  # --- History polling ---

  @impl true
  def handle_info(:poll_history, state) do
    state =
      case History.latest_turn(state.game_state.game_id) do
        {:ok, %{"turnid" => turn_id} = turn_data} ->
          new_turn? = state.last_turn_id != nil && turn_id != state.last_turn_id

          game_state =
            state.game_state
            |> LiveGameState.record_changed_history_response(turn_data)
            |> LiveGameState.send_reminder()
            |> LiveGameState.announce_moving()

          state = %{state | game_state: game_state, last_turn_id: turn_id}
          if new_turn?, do: start_view_screen_burst(state), else: state

        _ ->
          state
      end

    Process.send_after(self(), :poll_history, @history_interval)
    {:noreply, state}
  end

  # --- ViewScreen polling ---

  def handle_info(:poll_view_screen, %{view_screen_polls_remaining: 0} = state) do
    {:noreply, state}
  end

  def handle_info(:poll_view_screen, state) do
    remaining = state.view_screen_polls_remaining - 1

    state =
      case ViewScreen.get_game(state.game_state.game_id) do
        {:ok, view_screen} ->
          Games.upsert_game(view_screen)

          game_state =
            state.game_state
            |> LiveGameState.record_changed_view_screen_db(view_screen)
            |> LiveGameState.advance_turn()
            |> LiveGameState.fetch_log_if_unfogged()
            |> LiveGameState.infer_deaths_from_skip()
            |> LiveGameState.detect_eliminations()
            |> LiveGameState.announce_next_round()
            |> LiveGameState.announce_next_turn()
            |> LiveGameState.announce_winners()

          %{state | game_state: game_state, view_screen_polls_remaining: remaining}

        error ->
          Logger.error(
            "#{__MODULE__} ViewScreen fetch failed for game #{state.game_state.game_id}: #{inspect(error)}"
          )

          %{state | view_screen_polls_remaining: remaining}
      end

    if remaining > 0, do: Process.send_after(self(), :poll_view_screen, @view_screen_interval)
    {:noreply, state}
  end

  def handle_info({:ssl_closed, _}, state), do: {:noreply, state}

  # --- Game lifecycle ---

  @impl true
  def handle_cast(:finish_game, %{game_state: %{game_id: game_id}} = state) do
    Logger.info("#{__MODULE__} game #{game_id} finished — capturing log snapshot")
    Task.start(fn -> LogSnapshot.capture(game_id) end)
    {:stop, :normal, state}
  end

  def handle_cast(:fetch_log, %{game_state: %{game_id: game_id}} = state) do
    Logger.info("#{__MODULE__} fetching log for game #{game_id} after turn advance")

    Task.start(fn ->
      case Processor.refetch_and_process(game_id) do
        {:ok, counts} ->
          Logger.info("#{__MODULE__} log fetch complete for game #{game_id}: #{inspect(counts)}")

        {:error, reason} ->
          Logger.error("#{__MODULE__} log fetch failed for game #{game_id}: #{inspect(reason)}")
      end
    end)

    {:noreply, state}
  end

  # --- Private ---

  defp start_view_screen_burst(state) do
    send(self(), :poll_view_screen)
    %{state | view_screen_polls_remaining: @view_screen_max_polls}
  end
end
