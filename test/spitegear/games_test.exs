defmodule Spitegear.GamesTest do
  use Spitegear.DataCase, async: true

  alias Spitegear.{Repo, Games, Game, Turn}
  alias Spitegear.HTML.ViewScreen

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
end
