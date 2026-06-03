defmodule Spitegear.GamesTest do
  use Spitegear.DataCase, async: true

  import Ecto.Query

  alias Spitegear.Game
  alias Spitegear.GameDeath
  alias Spitegear.Games
  alias Spitegear.Wargear.HTTP.ViewScreen
  alias Spitegear.Repo
  alias Spitegear.Turn
  alias Spitegear.TurnHistory

  defp build_view_screen(attrs \\ []) do
    game_id = Keyword.get(attrs, :game_id, "11111")

    %ViewScreen{
      game_id: game_id,
      url: URI.parse("https://www.wargear.net/games/view/#{game_id}"),
      game_name: Keyword.get(attrs, :game_name, "Test Game"),
      board_name: Keyword.get(attrs, :board_name, "Classic"),
      created: Keyword.get(attrs, :created, "2024-01-01"),
      finished: Keyword.get(attrs, :finished, nil),
      winners: Keyword.get(attrs, :winners, [])
    }
  end

  defp build_turn(attrs \\ []) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %Turn{
      game_id: Keyword.get(attrs, :game_id, "11111"),
      player: %{name: "adam jormp jomp", slack_name: "@atom.r"},
      started: Keyword.get(attrs, :started, now),
      reminded: Keyword.get(attrs, :reminded, now),
      reminders: Keyword.get(attrs, :reminders, 0)
    }
  end

  describe "list_active_games/0" do
    test "returns only games with nil finished" do
      {:ok, _} = Games.upsert_game(build_view_screen(game_id: "1"))
      {:ok, _} = Games.upsert_game(build_view_screen(game_id: "2", finished: "2024-06-01"))

      active = Games.list_active_games()
      assert length(active) == 1
      assert hd(active).game_id == "1"
    end

    test "returns empty list when no active games" do
      {:ok, _} = Games.upsert_game(build_view_screen(finished: "2024-06-01"))
      assert Games.list_active_games() == []
    end
  end

  describe "upsert_game/1" do
    test "inserts a new game row" do
      assert {:ok, game} = Games.upsert_game(build_view_screen())
      assert game.game_id == "11111"
      assert game.game_name == "Test Game"
      assert game.finished == nil
    end

    test "updates existing row on conflicting game_id" do
      Games.upsert_game(build_view_screen())
      {:ok, _} = Games.upsert_game(build_view_screen(game_name: "Renamed"))
      assert Repo.aggregate(Game, :count) == 1
      assert Repo.get_by(Game, game_id: "11111").game_name == "Renamed"
    end

    test "stores winner names as array" do
      winner = %{name: "pants off vant hof", slack_name: "@cvanthof85"}
      {:ok, game} = Games.upsert_game(build_view_screen(winners: [winner]))
      assert game.winners == ["pants off vant hof"]
    end

    test "marks game as finished" do
      {:ok, game} = Games.upsert_game(build_view_screen(finished: "2024-12-01"))
      assert game.finished == "2024-12-01"
    end
  end

  describe "upsert_turn/1" do
    test "inserts a new turn row" do
      assert {:ok, _} = Games.upsert_turn(build_turn())
      assert Repo.aggregate(Turn, :count) == 1
    end

    test "updates the existing row on same game_id" do
      Games.upsert_turn(build_turn(reminders: 0))
      Games.upsert_turn(build_turn(reminders: 3))

      assert Repo.aggregate(Turn, :count) == 1
      assert Repo.get_by(Turn, game_id: "11111").reminders == 3
    end

    test "updates reminded timestamp" do
      later = DateTime.utc_now() |> DateTime.add(3600) |> DateTime.truncate(:second)
      Games.upsert_turn(build_turn())
      Games.upsert_turn(build_turn(reminded: later))

      assert Repo.get_by(Turn, game_id: "11111").reminded == later
    end

    test "stores player name" do
      Games.upsert_turn(build_turn())
      assert Repo.get_by(Turn, game_id: "11111").player_name == "adam jormp jomp"
    end
  end

  describe "get_current_turn/1" do
    test "returns nil when no turn exists for game" do
      assert Games.get_current_turn("99999") == nil
    end

    test "returns turn with player struct populated from name" do
      Games.upsert_turn(build_turn())
      turn = Games.get_current_turn("11111")

      assert turn.game_id == "11111"
      assert turn.player.name == "adam jormp jomp"
      assert turn.player.slack_name == "@atom.r"
    end

    test "returns reminders count" do
      Games.upsert_turn(build_turn(reminders: 2))
      assert Games.get_current_turn("11111").reminders == 2
    end
  end

  describe "record_completed_turn/2" do
    test "inserts a turn_history record with correct fields" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      ended = now |> DateTime.add(300)
      turn = build_turn(started: now)

      assert {:ok, record} = Games.record_completed_turn(turn, ended)
      assert record.game_id == "11111"
      assert record.player_name == "adam jormp jomp"
      assert record.started == now
      assert record.ended == ended
    end

    test "allows multiple history records for the same game and player" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      turn = build_turn(started: now)

      Games.record_completed_turn(turn, DateTime.add(now, 100))
      Games.record_completed_turn(turn, DateTime.add(now, 200))

      assert Repo.aggregate(TurnHistory, :count) == 2
    end
  end

  describe "record_death/3" do
    test "inserts a game_death record" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      assert {:ok, death} = Games.record_death("11111", "adam", now)
      assert death.game_id == "11111"
      assert death.player_name == "adam"
      assert death.eliminated_at == now
    end

    test "is idempotent — second insert is a no-op" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      {:ok, _} = Games.record_death("11111", "adam", now)
      {:ok, _} = Games.record_death("11111", "adam", now)

      assert Repo.aggregate(from(d in GameDeath, where: d.game_id == "11111"), :count) == 1
    end
  end

  describe "completed_rounds/1" do
    test "returns 0 with no turn history" do
      assert Games.completed_rounds("11111") == 0
    end

    test "counts complete rounds from turn sequence" do
      insert_turn_sequence("11111", ~w[adam bob adam bob adam])
      assert Games.completed_rounds("11111") == 2
    end

    test "returns 5 at the five-round boundary (triggers stats post)" do
      insert_turn_sequence("11111", ~w[adam bob adam bob adam bob adam bob adam bob])
      completed = Games.completed_rounds("11111")
      assert completed == 5
      assert rem(completed, 5) == 0
    end

    test "does not count a partial round as complete" do
      insert_turn_sequence("11111", ~w[adam bob adam bob adam bob adam bob adam])
      assert Games.completed_rounds("11111") == 4
    end

    test "infers eliminated player from turn sequence gaps" do
      # bob eliminated after round 2; adam continues alone for rounds 3-5
      insert_turn_sequence("11111", ~w[adam bob adam bob adam adam adam])
      assert Games.completed_rounds("11111") == 5
    end

    test "increments when the last player in a round finishes — triggers round announcement" do
      base = ~U[2024-01-01 00:00:00Z]

      Repo.insert!(%TurnHistory{
        game_id: "11111",
        player_name: "adam",
        started: base,
        ended: DateTime.add(base, 599)
      })

      Repo.insert!(%TurnHistory{
        game_id: "11111",
        player_name: "bob",
        started: DateTime.add(base, 600),
        ended: DateTime.add(base, 1199)
      })

      # [adam, bob] — no repeat yet, round 1 not counted
      assert Games.completed_rounds("11111") == 0

      Repo.insert!(%TurnHistory{
        game_id: "11111",
        player_name: "adam",
        started: DateTime.add(base, 1200),
        ended: DateTime.add(base, 1799)
      })

      # [adam, bob, adam] — adam repeated, round 1 is now complete
      assert Games.completed_rounds("11111") == 1
    end
  end

  describe "turn_stats/1" do
    test "returns avg, fastest, and slowest durations per player" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      insert_turns_with_durations("11111", "adam", now, [60, 120, 180])

      stats = Games.turn_stats("11111")
      assert length(stats) == 1

      [s] = stats
      assert s.player_name == "adam"
      assert s.count == 3
      assert s.avg_seconds == 120
      assert s.fastest_seconds == 60
      assert s.slowest_seconds == 180
    end

    test "returns stats for multiple players sorted by name" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      insert_turns_with_durations("11111", "zara", now, [100])
      insert_turns_with_durations("11111", "adam", now, [200])

      stats = Games.turn_stats("11111")
      assert Enum.map(stats, & &1.player_name) == ["adam", "zara"]
    end
  end

  defp insert_turn_sequence(game_id, players) do
    base = ~U[2024-01-01 00:00:00Z]

    Enum.with_index(players, fn player, i ->
      started = DateTime.add(base, i * 600)
      ended = DateTime.add(base, i * 600 + 599)

      Repo.insert!(%TurnHistory{
        game_id: game_id,
        player_name: player,
        started: started,
        ended: ended
      })
    end)
  end

  defp insert_turns_with_durations(game_id, player_name, base_time, durations) do
    Enum.reduce(durations, base_time, fn duration, offset ->
      started = offset
      ended = DateTime.add(offset, duration)

      Repo.insert!(%TurnHistory{
        game_id: game_id,
        player_name: player_name,
        started: started,
        ended: ended
      })

      DateTime.add(ended, 60)
    end)
  end
end
