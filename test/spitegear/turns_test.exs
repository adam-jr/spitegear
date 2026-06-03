defmodule Spitegear.TurnsTest do
  use Spitegear.DataCase, async: true

  alias Spitegear.Repo
  alias Spitegear.TurnHistory
  alias Spitegear.TurnHistory.Round
  alias Spitegear.Turns

  @game_id "11111"
  @base ~U[2024-01-01 00:00:00Z]

  defp insert_turn(player, offset_seconds) do
    started = DateTime.add(@base, offset_seconds)
    ended = DateTime.add(@base, offset_seconds + 599)
    Repo.insert!(%TurnHistory{game_id: @game_id, player_name: player, started: started, ended: ended})
  end

  describe "list_rounds/1" do
    test "returns [] with no history" do
      assert Turns.list_rounds(@game_id) == []
    end

    test "single player, single turn — one incomplete round" do
      insert_turn("adam", 0)

      assert [%Round{turns: [t], complete: false}] = Turns.list_rounds(@game_id)
      assert t.player_name == "adam"
    end

    test "two players, no repeat — one incomplete round with both" do
      insert_turn("adam", 0)
      insert_turn("bob", 600)

      assert [%Round{turns: turns, complete: false}] = Turns.list_rounds(@game_id)
      assert Enum.map(turns, & &1.player_name) == ["adam", "bob"]
    end

    test "player repeats — first round complete, second in progress" do
      insert_turn("adam", 0)
      insert_turn("bob", 600)
      insert_turn("adam", 1200)

      assert [r1, r2] = Turns.list_rounds(@game_id)
      assert r1.complete == true
      assert Enum.map(r1.turns, & &1.player_name) == ["adam", "bob"]
      assert r2.complete == false
      assert Enum.map(r2.turns, & &1.player_name) == ["adam"]
    end

    test "three players, two full rounds, one in progress" do
      insert_turn("adam", 0)
      insert_turn("bob", 600)
      insert_turn("carol", 1200)
      insert_turn("adam", 1800)
      insert_turn("bob", 2400)
      insert_turn("carol", 3000)
      insert_turn("adam", 3600)

      assert [r1, r2, r3] = Turns.list_rounds(@game_id)
      assert r1.complete == true
      assert r2.complete == true
      assert r3.complete == false
      assert Enum.map(r3.turns, & &1.player_name) == ["adam"]
    end

    test "handles eliminations — player disappears mid-game" do
      # bob is eliminated after round 1; adam continues alone
      insert_turn("adam", 0)
      insert_turn("bob", 600)
      insert_turn("adam", 1200)
      insert_turn("adam", 1800)

      assert [r1, r2, r3] = Turns.list_rounds(@game_id)
      assert r1.complete == true
      assert Enum.map(r1.turns, & &1.player_name) == ["adam", "bob"]
      assert r2.complete == true
      assert Enum.map(r2.turns, & &1.player_name) == ["adam"]
      assert r3.complete == false
      assert Enum.map(r3.turns, & &1.player_name) == ["adam"]
    end
  end
end
