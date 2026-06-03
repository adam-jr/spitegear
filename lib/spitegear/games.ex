defmodule Spitegear.Games do
  @moduledoc """
  Context for reading and writing game state.

  Covers games, active turns, turn history, player deaths, and poller lifecycle.
  """
  import Ecto.Query
  alias Spitegear.Game
  alias Spitegear.GameDeath
  alias Spitegear.GameLogSnapshot
  alias Spitegear.HTML.Player
  alias Spitegear.Repo
  alias Spitegear.Turn
  alias Spitegear.TurnHistory
  alias Spitegear.Wargear.HTTP.LogSnapshot
  alias Spitegear.Wargear.HTTP.ViewScreen
  alias Spitegear.Worker.GamePoller
  alias Spitegear.Worker.GamePollerNew

  @type game_id :: String.t()

  @type turn_stat :: %{
          player_name: String.t(),
          count: pos_integer(),
          avg_seconds: integer(),
          fastest_seconds: integer(),
          slowest_seconds: integer()
        }

  @doc "Returns all active games (finished IS NULL, not undiscovered stubs)."
  @spec list_active_games() :: [Game.t()]
  def list_active_games do
    Repo.all(from(g in Game, where: is_nil(g.finished) and not g.discovered))
  end

  @doc "All tracked games (active + finished, excludes undiscovered stubs)."
  @spec list_all_games() :: [Game.t()]
  def list_all_games do
    Repo.all(from(g in Game, where: not g.discovered))
  end

  @doc "Returns finished games sorted by finish date descending."
  @spec list_finished_games() :: [Game.t()]
  def list_finished_games do
    Repo.all(from(g in Game, where: not is_nil(g.finished)))
    |> Enum.sort_by(&parse_finished_date(&1.finished), {:desc, NaiveDateTime})
  end

  @doc """
  Returns all-time win counts per player, sorted descending by wins.
  Each entry is `{player_name, win_count}`.
  """
  @spec leaderboard() :: [{String.t(), non_neg_integer()}]
  def leaderboard do
    Repo.all(from(g in Game, where: not is_nil(g.finished), select: g.winners))
    |> List.flatten()
    |> Enum.frequencies()
    |> Enum.sort_by(&elem(&1, 1), :desc)
  end

  @months ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)
          |> Enum.with_index(1)
          |> Map.new()

  @doc """
  Parses a wargear date string like "Wed Sep 09, 2020 10:31" into a NaiveDateTime.
  Returns nil on failure.
  """
  @spec parse_game_date(String.t() | nil) :: NaiveDateTime.t() | nil
  def parse_game_date(nil), do: nil

  def parse_game_date(date_str) do
    case Regex.run(~r/\w+ (\w+) (\d+), (\d+) (\d+):(\d+)/, date_str) do
      [_, mon, day, year, hour, min] ->
        NaiveDateTime.new!(
          String.to_integer(year),
          Map.get(@months, mon, 1),
          String.to_integer(day),
          String.to_integer(hour),
          String.to_integer(min),
          0
        )

      _ ->
        nil
    end
  end

  # Parses "Wed Sep 09, 2020 10:31" → NaiveDateTime for sorting
  defp parse_finished_date(nil), do: ~N[1970-01-01 00:00:00]
  defp parse_finished_date(s), do: parse_game_date(s) || ~N[1970-01-01 00:00:00]

  @doc "Returns games that were discovered via Slack but not yet fetched from wargear.net."
  @spec list_unfetched_games() :: [Game.t()]
  def list_unfetched_games do
    Repo.all(from(g in Game, where: g.discovered, order_by: [desc: g.inserted_at]))
  end

  @doc "Returns the set of game IDs that have a stored log snapshot."
  @spec game_ids_with_snapshots() :: MapSet.t(String.t())
  def game_ids_with_snapshots do
    Repo.all(from(s in GameLogSnapshot, select: s.game_id))
    |> Enum.map(&Integer.to_string/1)
    |> MapSet.new()
  end

  @doc "Inserts or updates a game row from a `ViewScreen`."
  @spec upsert_game(ViewScreen.t()) :: {:ok, Game.t()} | {:error, Ecto.Changeset.t()}
  def upsert_game(view_screen) do
    player_colors =
      view_screen.players
      |> Enum.filter(& &1.color)
      |> Map.new(&{&1.name, &1.color})

    Repo.insert(
      %Game{
        game_id: view_screen.game_id,
        url: URI.to_string(view_screen.url),
        game_name: view_screen.game_name,
        board_name: view_screen.board_name,
        created: view_screen.created,
        finished: view_screen.finished,
        winners: Enum.map(view_screen.winners, & &1.name),
        player_colors: player_colors,
        discovered: false
      },
      on_conflict:
        {:replace,
         [
           :url,
           :game_name,
           :board_name,
           :created,
           :finished,
           :winners,
           :player_colors,
           :discovered,
           :updated_at
         ]},
      conflict_target: :game_id
    )
  end

  @doc """
  Returns the current turn for `game_id`, with the `player` virtual field populated.
  Returns `nil` if no turn exists yet.
  """
  @spec get_current_turn(game_id()) :: Turn.t() | nil
  def get_current_turn(game_id) do
    case Repo.get_by(Turn, game_id: game_id) do
      nil -> nil
      turn -> %{turn | player: Player.from_name(turn.player_name)}
    end
  end

  @doc "Inserts or updates the current turn row for `turn.game_id`."
  @spec upsert_turn(Turn.t()) :: {:ok, Turn.t()} | {:error, Ecto.Changeset.t()}
  def upsert_turn(turn) do
    Repo.insert(
      %Turn{
        game_id: turn.game_id,
        player_name: turn.player.name,
        started: turn.started,
        reminded: turn.reminded,
        reminders: turn.reminders,
        moving_announced: turn.moving_announced
      },
      on_conflict:
        {:replace,
         [:player_name, :started, :reminded, :reminders, :moving_announced, :updated_at]},
      conflict_target: :game_id
    )
  end

  @doc "Appends a completed-turn record to `turn_history`."
  @spec record_completed_turn(Turn.t(), DateTime.t()) ::
          {:ok, TurnHistory.t()} | {:error, Ecto.Changeset.t()}
  def record_completed_turn(turn, ended) do
    Repo.insert(%TurnHistory{
      game_id: turn.game_id,
      player_name: turn.player.name,
      started: turn.started,
      ended: ended
    })
  end

  @doc "Records a player elimination. Safe to call more than once — duplicate inserts are ignored."
  @spec record_death(game_id(), String.t(), DateTime.t()) ::
          {:ok, GameDeath.t()} | {:error, Ecto.Changeset.t()}
  def record_death(game_id, player_name, eliminated_at) do
    Repo.insert(
      %GameDeath{game_id: game_id, player_name: player_name, eliminated_at: eliminated_at},
      on_conflict: :nothing,
      conflict_target: [:game_id, :player_name]
    )
  end

  @doc """
  Returns the number of completed rounds for `game_id`.

  A round is complete when every active player has taken at least one turn.
  The algorithm walks `turn_history` in chronological order and counts a new
  round each time a player reappears, so it handles eliminations mid-game
  without depending on the `game_deaths` table.
  """
  @spec completed_rounds(game_id()) :: non_neg_integer()
  def completed_rounds(game_id) do
    Repo.all(
      from(t in TurnHistory,
        where: t.game_id == ^game_id,
        order_by: [asc: t.started],
        select: t.player_name
      )
    )
    |> count_completed_rounds()
  end

  defp count_completed_rounds([]), do: 0

  defp count_completed_rounds(turns) do
    {rounds, current_cycle, last_complete_cycle} =
      Enum.reduce(turns, {0, [], []}, fn player, {rounds, cycle, last_complete} ->
        if player in cycle do
          {rounds + 1, [player], cycle}
        else
          {rounds, [player | cycle], last_complete}
        end
      end)

    if MapSet.equal?(MapSet.new(current_cycle), MapSet.new(last_complete_cycle)) do
      rounds + 1
    else
      rounds
    end
  end

  @doc "Returns per-player turn duration statistics for `game_id`, sorted by player name."
  @spec turn_stats(game_id()) :: [turn_stat()]
  def turn_stats(game_id) do
    Repo.all(
      from(t in TurnHistory,
        where: t.game_id == ^game_id,
        select: %{player_name: t.player_name, started: t.started, ended: t.ended}
      )
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

  @doc "Returns the total number of completed turns recorded for `game_id`."
  @spec completed_turn_count(game_id()) :: non_neg_integer()
  def completed_turn_count(game_id) do
    Repo.aggregate(from(t in TurnHistory, where: t.game_id == ^game_id), :count)
  end

  @doc "Returns the `Game` row for `game_id`, or `nil` if not found."
  @spec get_game(game_id()) :: Game.t() | nil
  def get_game(game_id) do
    Repo.get_by(Game, game_id: game_id)
  end

  @doc "Returns all recorded player deaths for `game_id`."
  @spec list_deaths(game_id()) :: [GameDeath.t()]
  def list_deaths(game_id) do
    Repo.all(from(d in GameDeath, where: d.game_id == ^game_id))
  end

  @doc """
  Returns all players seen in `turn_history` for `game_id`, with alive/eliminated status.

  Alive players are listed first; eliminated players follow, sorted by elimination
  time descending.
  """
  @spec list_player_statuses(game_id()) :: [
          %{player_name: String.t(), alive: boolean(), eliminated_at: DateTime.t() | nil}
        ]
  def list_player_statuses(game_id) do
    all_players =
      Repo.all(
        from(t in TurnHistory,
          where: t.game_id == ^game_id,
          select: t.player_name,
          distinct: true
        )
      )

    dead =
      Repo.all(from(d in GameDeath, where: d.game_id == ^game_id))
      |> Map.new(&{&1.player_name, &1.eliminated_at})

    alive = Enum.reject(all_players, &Map.has_key?(dead, &1))

    alive_entries = Enum.map(alive, &%{player_name: &1, alive: true, eliminated_at: nil})

    dead_entries =
      Enum.map(dead, fn {name, at} -> %{player_name: name, alive: false, eliminated_at: at} end)
      |> Enum.sort_by(& &1.eliminated_at, {:desc, DateTime})

    alive_entries ++ dead_entries
  end

  @doc "Returns the most recent `limit` turns for `game_id`, newest first."
  @spec list_turn_history(game_id(), pos_integer()) :: [TurnHistory.t()]
  def list_turn_history(game_id, limit \\ 30) do
    Repo.all(
      from(t in TurnHistory,
        where: t.game_id == ^game_id,
        order_by: [desc: t.started],
        limit: ^limit
      )
    )
  end

  @doc """
  Fetches a completed game from wargear.net, upserts it into the games table
  with full metadata (name, board, finished date, winners), and snapshots the
  raw HTML log. Safe to call more than once — both operations are idempotent.
  """
  @spec fetch_historical_game(game_id()) ::
          {:ok, ViewScreen.t()} | :error | {:error, Ecto.Changeset.t()}
  def fetch_historical_game(game_id) do
    with {:ok, view_screen} <- ViewScreen.get_game(game_id),
         {:ok, _game} <- upsert_game(view_screen),
         {:ok, _snapshot} <- LogSnapshot.capture(game_id) do
      {:ok, view_screen}
    end
  end

  @doc """
  Refreshes a game's viewscreen metadata (name, board, winners, player colors)
  without re-fetching the log snapshot. Safe to re-run.
  """
  @spec refresh_viewscreen(game_id()) ::
          {:ok, ViewScreen.t()} | :error | {:error, Ecto.Changeset.t()}
  def refresh_viewscreen(game_id) do
    with {:ok, view_screen} <- ViewScreen.get_game(game_id),
         {:ok, _game} <- upsert_game(view_screen) do
      {:ok, view_screen}
    end
  end

  @doc "Inserts a game stub. No-op if the game already exists."
  @spec add_game(game_id()) :: {:ok, Game.t()} | {:error, Ecto.Changeset.t()}
  def add_game(game_id) do
    Repo.insert(%Game{game_id: game_id},
      on_conflict: :nothing,
      conflict_target: :game_id
    )
  end

  @doc "Inserts a discovered-game stub (seen in Slack, not yet fetched). No-op if already present."
  @spec add_discovered_game(game_id()) :: {:ok, Game.t()} | {:error, Ecto.Changeset.t()}
  def add_discovered_game(game_id) do
    Repo.insert(%Game{game_id: game_id, discovered: true},
      on_conflict: :nothing,
      conflict_target: :game_id
    )
  end

  @doc "Deletes the discovered-game stub for `game_id`. No-op if it has already been fetched."
  @spec delete_discovered_game(game_id()) :: :ok
  def delete_discovered_game(game_id) do
    Repo.delete_all(from(g in Game, where: g.game_id == ^game_id and g.discovered))
    :ok
  end

  @doc "Starts a `GamePoller` for `game_id` under `GameSupervisor`."
  @spec start_poller(game_id()) ::
          {:ok, pid()} | {:error, {:already_started, pid()} | :max_children | term()}
  def start_poller(game_id) do
    DynamicSupervisor.start_child(
      GameSupervisor,
      GamePoller.child_spec(game_id: game_id)
    )
  end

  @doc "Terminates the running `GamePoller` for `game_id`. No-op if none is running."
  @spec stop_poller(game_id()) :: :ok | {:error, :not_found | term()}
  def stop_poller(game_id) do
    case Process.whereis(poller_name(game_id)) do
      nil -> :ok
      pid -> DynamicSupervisor.terminate_child(GameSupervisor, pid)
    end
  end

  @doc "Returns `true` if a `GamePoller` is currently running for `game_id`."
  @spec poller_alive?(game_id()) :: boolean()
  def poller_alive?(game_id) do
    Process.whereis(poller_name(game_id)) != nil
  end

  @doc "Returns the last seen `turnid` from the running poller, or `nil` if no poller is active."
  @spec poller_turn_id(game_id()) :: String.t() | nil
  def poller_turn_id(game_id) do
    case Process.whereis(poller_name(game_id)) do
      nil -> nil
      pid -> :sys.get_state(pid).last_turn_id
    end
  end

  @doc "Starts a `GamePoller` for each active game. Called once at application startup."
  @spec resume_games() :: :ok
  def resume_games do
    Enum.each(list_active_games(), fn game ->
      DynamicSupervisor.start_child(
        GameSupervisor,
        GamePoller.child_spec(game_id: game.game_id)
      )
    end)
  end

  @doc "Starts a `GamePollerNew` for each active game. Called once at application startup."
  @spec resume_new_pollers() :: :ok
  def resume_new_pollers do
    Enum.each(list_active_games(), fn game ->
      DynamicSupervisor.start_child(
        GameSupervisor,
        GamePollerNew.child_spec(game_id: game.game_id)
      )
    end)
  end

  @doc "Starts a `GamePollerNew` for `game_id` alongside any existing poller."
  @spec start_new_poller(game_id()) ::
          {:ok, pid()} | {:error, {:already_started, pid()} | :max_children | term()}
  def start_new_poller(game_id) do
    DynamicSupervisor.start_child(
      GameSupervisor,
      GamePollerNew.child_spec(game_id: game_id)
    )
  end

  @doc "Terminates the running `GamePollerNew` for `game_id`. No-op if none is running."
  @spec stop_new_poller(game_id()) :: :ok | {:error, :not_found | term()}
  def stop_new_poller(game_id) do
    case Process.whereis(GamePollerNew.name(game_id)) do
      nil -> :ok
      pid -> DynamicSupervisor.terminate_child(GameSupervisor, pid)
    end
  end

  @doc "Returns `true` if a `GamePollerNew` is currently running for `game_id`."
  @spec new_poller_alive?(game_id()) :: boolean()
  def new_poller_alive?(game_id), do: GamePollerNew.alive?(game_id)

  defp poller_name(game_id), do: GamePoller.name(game_id)
end
