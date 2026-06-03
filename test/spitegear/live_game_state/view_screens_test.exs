defmodule Spitegear.LiveGameState.ViewScreensTest do
  use Spitegear.DataCase, async: true

  alias Spitegear.LiveGameState.ViewScreens
  alias Spitegear.LiveGameState.WargearViewScreenDb
  alias Spitegear.Repo
  alias Spitegear.Wargear.HTTP.ViewScreen, as: RawViewScreen

  defp player(name), do: %{name: name, slack_name: "@#{name}"}

  defp build_raw(attrs \\ []) do
    %RawViewScreen{
      game_id: Keyword.get(attrs, :game_id, "11111"),
      game_name: "Test Game",
      board_name: "Classic",
      created: "2024-01-01",
      finished: Keyword.get(attrs, :finished, nil),
      current_player: Keyword.get(attrs, :current_player, player("adam")),
      players: Keyword.get(attrs, :players, [player("adam"), player("bob")]),
      eliminated: Keyword.get(attrs, :eliminated, []),
      winners: Keyword.get(attrs, :winners, []),
      fogged?: Keyword.get(attrs, :fogged?, false)
    }
  end

  defp insert_snapshot(attrs \\ []) do
    Repo.insert!(%WargearViewScreenDb{
      game_id: Keyword.get(attrs, :game_id, "11111"),
      current_player_name: Keyword.get(attrs, :current_player_name, "adam"),
      players: [],
      eliminated: [],
      winners: [],
      fogged: false
    })
  end

  describe "get_latest/1" do
    test "returns nil when no snapshots exist" do
      assert ViewScreens.get_latest("11111") == nil
    end

    test "returns the most recently inserted snapshot" do
      Repo.insert!(%WargearViewScreenDb{
        game_id: "11111",
        current_player_name: "adam",
        players: [],
        eliminated: [],
        winners: [],
        fogged: false,
        inserted_at: ~U[2024-01-01 00:00:00Z],
        updated_at: ~U[2024-01-01 00:00:00Z]
      })

      Repo.insert!(%WargearViewScreenDb{
        game_id: "11111",
        current_player_name: "bob",
        players: [],
        eliminated: [],
        winners: [],
        fogged: false,
        inserted_at: ~U[2024-01-02 00:00:00Z],
        updated_at: ~U[2024-01-02 00:00:00Z]
      })

      assert ViewScreens.get_latest("11111").current_player_name == "bob"
    end

    test "does not return snapshots from other games" do
      insert_snapshot(game_id: "99999")
      assert ViewScreens.get_latest("11111") == nil
    end
  end

  describe "record_if_changed/1" do
    test "inserts a snapshot when none exists yet" do
      assert {:ok, %WargearViewScreenDb{}} = ViewScreens.record_if_changed(build_raw())
      assert Repo.aggregate(WargearViewScreenDb, :count) == 1
    end

    test "inserts a new snapshot when current player changes" do
      ViewScreens.record_if_changed(build_raw(current_player: player("adam")))

      assert {:ok, %WargearViewScreenDb{}} =
               ViewScreens.record_if_changed(build_raw(current_player: player("bob")))

      assert Repo.aggregate(WargearViewScreenDb, :count) == 2
    end

    test "returns :unchanged when nothing has changed" do
      raw = build_raw()
      ViewScreens.record_if_changed(raw)
      assert {:ok, :unchanged} = ViewScreens.record_if_changed(raw)
      assert Repo.aggregate(WargearViewScreenDb, :count) == 1
    end

    test "inserts when a player is newly eliminated" do
      ViewScreens.record_if_changed(build_raw(eliminated: []))

      assert {:ok, %WargearViewScreenDb{}} =
               ViewScreens.record_if_changed(build_raw(eliminated: [player("bob")]))

      assert Repo.aggregate(WargearViewScreenDb, :count) == 2
    end

    test "inserts when winners are set" do
      ViewScreens.record_if_changed(build_raw(winners: []))

      assert {:ok, %WargearViewScreenDb{}} =
               ViewScreens.record_if_changed(build_raw(winners: [player("adam")]))

      assert Repo.aggregate(WargearViewScreenDb, :count) == 2
    end

    test "inserts when game is finished" do
      ViewScreens.record_if_changed(build_raw(finished: nil))

      assert {:ok, %WargearViewScreenDb{}} =
               ViewScreens.record_if_changed(build_raw(finished: "2024-12-01"))

      assert Repo.aggregate(WargearViewScreenDb, :count) == 2
    end

    test "inserts when fogged state changes" do
      ViewScreens.record_if_changed(build_raw(fogged?: false))

      assert {:ok, %WargearViewScreenDb{}} =
               ViewScreens.record_if_changed(build_raw(fogged?: true))

      assert Repo.aggregate(WargearViewScreenDb, :count) == 2
    end

    test "stores player name and slack_name in players list" do
      ViewScreens.record_if_changed(build_raw())
      [snapshot] = Repo.all(WargearViewScreenDb)

      assert snapshot.players == [
               %{"name" => "adam", "slack_name" => "@adam"},
               %{"name" => "bob", "slack_name" => "@bob"}
             ]
    end
  end

  describe "prune/1" do
    test "deletes snapshots older than the given number of days" do
      old = DateTime.utc_now() |> DateTime.add(-91 * 86_400) |> DateTime.truncate(:second)

      Repo.insert!(%WargearViewScreenDb{
        game_id: "11111",
        current_player_name: "adam",
        players: [],
        eliminated: [],
        winners: [],
        fogged: false,
        inserted_at: old,
        updated_at: old
      })

      insert_snapshot()

      {count, _} = ViewScreens.prune(90)
      assert count == 1
      assert Repo.aggregate(WargearViewScreenDb, :count) == 1
    end

    test "leaves recent snapshots untouched" do
      insert_snapshot()
      {count, _} = ViewScreens.prune(90)
      assert count == 0
      assert Repo.aggregate(WargearViewScreenDb, :count) == 1
    end
  end
end
