defmodule Spitegear.LiveGameState.HistoryResponsesTest do
  use Spitegear.DataCase, async: true

  alias Spitegear.LiveGameState.HistoryResponses
  alias Spitegear.LiveGameState.WargearHistoryApiResponseDb
  alias Spitegear.Repo

  defp turn_data(turnid), do: %{"turnid" => turnid, "player" => "adam"}

  describe "get_latest/1" do
    test "returns nil when no records exist" do
      assert HistoryResponses.get_latest("11111") == nil
    end

    test "returns the most recently inserted record" do
      Repo.insert!(%WargearHistoryApiResponseDb{
        game_id: "11111",
        turn_data: turn_data("1"),
        inserted_at: ~U[2024-01-01 00:00:00Z],
        updated_at: ~U[2024-01-01 00:00:00Z]
      })

      Repo.insert!(%WargearHistoryApiResponseDb{
        game_id: "11111",
        turn_data: turn_data("2"),
        inserted_at: ~U[2024-01-02 00:00:00Z],
        updated_at: ~U[2024-01-02 00:00:00Z]
      })

      assert HistoryResponses.get_latest("11111").turn_data["turnid"] == "2"
    end

    test "does not return records from other games" do
      Repo.insert!(%WargearHistoryApiResponseDb{game_id: "99999", turn_data: turn_data("1")})
      assert HistoryResponses.get_latest("11111") == nil
    end
  end

  describe "record_if_changed/2" do
    test "inserts a record when none exists yet" do
      assert {:ok, %WargearHistoryApiResponseDb{}} =
               HistoryResponses.record_if_changed("11111", turn_data("1"))

      assert Repo.aggregate(WargearHistoryApiResponseDb, :count) == 1
    end

    test "inserts a new record when turnid changes" do
      HistoryResponses.record_if_changed("11111", turn_data("1"))

      assert {:ok, %WargearHistoryApiResponseDb{}} =
               HistoryResponses.record_if_changed("11111", turn_data("2"))

      assert Repo.aggregate(WargearHistoryApiResponseDb, :count) == 2
    end

    test "returns :unchanged when turnid has not changed" do
      HistoryResponses.record_if_changed("11111", turn_data("1"))
      assert {:ok, :unchanged} = HistoryResponses.record_if_changed("11111", turn_data("1"))
      assert Repo.aggregate(WargearHistoryApiResponseDb, :count) == 1
    end

    test "stores the full turn_data map" do
      data = %{"turnid" => "42", "player" => "adam", "extra" => "field"}
      HistoryResponses.record_if_changed("11111", data)
      assert Repo.one(WargearHistoryApiResponseDb).turn_data == data
    end

    test "scopes records by game_id" do
      HistoryResponses.record_if_changed("11111", turn_data("1"))
      HistoryResponses.record_if_changed("22222", turn_data("1"))
      assert Repo.aggregate(WargearHistoryApiResponseDb, :count) == 2
    end
  end

  describe "prune/1" do
    test "deletes records older than the given number of days" do
      old = DateTime.utc_now() |> DateTime.add(-91 * 86_400) |> DateTime.truncate(:second)

      Repo.insert!(%WargearHistoryApiResponseDb{
        game_id: "11111",
        turn_data: turn_data("1"),
        inserted_at: old,
        updated_at: old
      })

      Repo.insert!(%WargearHistoryApiResponseDb{game_id: "11111", turn_data: turn_data("2")})

      {count, _} = HistoryResponses.prune(90)
      assert count == 1
      assert Repo.aggregate(WargearHistoryApiResponseDb, :count) == 1
    end

    test "leaves recent records untouched" do
      Repo.insert!(%WargearHistoryApiResponseDb{game_id: "11111", turn_data: turn_data("1")})
      {count, _} = HistoryResponses.prune(90)
      assert count == 0
    end
  end
end
