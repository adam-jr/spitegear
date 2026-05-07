defmodule Spitegear.Games do
  import Ecto.Query
  alias Spitegear.{Repo, Game, Turn, TurnHistory}

  def list_active_games do
    Repo.all(from g in Game, where: is_nil(g.finished))
  end

  def upsert_game(view_screen) do
    Repo.insert(
      %Game{
        game_id: view_screen.game_id,
        url: URI.to_string(view_screen.url),
        game_name: view_screen.game_name,
        board_name: view_screen.board_name,
        created: view_screen.created,
        finished: view_screen.finished,
        winners: Enum.map(view_screen.winners, & &1.name)
      },
      on_conflict: {:replace, [:url, :game_name, :board_name, :created, :finished, :winners, :updated_at]},
      conflict_target: :game_id
    )
  end

  def get_current_turn(game_id) do
    case Repo.get_by(Turn, game_id: game_id) do
      nil -> nil
      turn -> %{turn | player: Spitegear.HTML.Player.from_name(turn.player_name)}
    end
  end

  def upsert_turn(turn) do
    Repo.insert(
      %Turn{
        game_id: turn.game_id,
        player_name: turn.player.name,
        started: turn.started,
        reminded: turn.reminded,
        reminders: turn.reminders
      },
      on_conflict: {:replace, [:player_name, :started, :reminded, :reminders, :updated_at]},
      conflict_target: :game_id
    )
  end

  def record_completed_turn(turn, ended) do
    Repo.insert(%TurnHistory{
      game_id: turn.game_id,
      player_name: turn.player.name,
      started: turn.started,
      ended: ended
    })
  end

  def turn_stats(game_id) do
    Repo.all(
      from t in TurnHistory,
        where: t.game_id == ^game_id,
        select: %{player_name: t.player_name, started: t.started, ended: t.ended}
    )
    |> Enum.group_by(& &1.player_name)
    |> Enum.map(fn {player_name, turns} ->
      durations = Enum.map(turns, &DateTime.diff(&1.ended, &1.started))
      %{
        player_name: player_name,
        count: length(turns),
        avg_seconds: Enum.sum(durations) |> div(length(durations)),
        fastest_seconds: Enum.min(durations),
        slowest_seconds: Enum.max(durations)
      }
    end)
    |> Enum.sort_by(& &1.player_name)
  end

  def completed_turn_count(game_id) do
    Repo.aggregate(from(t in TurnHistory, where: t.game_id == ^game_id), :count)
  end

  def get_game(game_id) do
    Repo.get_by(Game, game_id: game_id)
  end

  def list_turn_history(game_id, limit \\ 30) do
    Repo.all(
      from t in TurnHistory,
        where: t.game_id == ^game_id,
        order_by: [desc: t.started],
        limit: ^limit
    )
  end

  def add_game(game_id) do
    Repo.insert(%Game{game_id: game_id},
      on_conflict: :nothing,
      conflict_target: :game_id
    )
  end

  def start_poller(game_id) do
    DynamicSupervisor.start_child(
      GameSupervisor,
      Spitegear.Worker.GamePoller.child_spec(game_id: game_id)
    )
  end

  def stop_poller(game_id) do
    case Process.whereis(poller_name(game_id)) do
      nil -> :ok
      pid -> DynamicSupervisor.terminate_child(GameSupervisor, pid)
    end
  end

  def poller_alive?(game_id) do
    Process.whereis(poller_name(game_id)) != nil
  end

  def resume_games do
    Enum.each(list_active_games(), fn game ->
      DynamicSupervisor.start_child(
        GameSupervisor,
        Spitegear.Worker.GamePoller.child_spec(game_id: game.game_id)
      )
    end)
  end

  defp poller_name(game_id), do: Spitegear.Worker.GamePoller.name(game_id)
end
