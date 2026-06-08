defmodule Spitegear.LiveGameState.TurnsTest do
  use Spitegear.DataCase, async: true

  alias Spitegear.LiveGameState.Turn
  alias Spitegear.LiveGameState.Turns
  alias Spitegear.Repo
  alias Spitegear.TurnHistory

  @base ~U[2024-01-01 12:00:00Z]

  defp insert_turn(attrs \\ []) do
    Repo.insert!(%Turn{
      game_id: Keyword.get(attrs, :game_id, "11111"),
      player_name: Keyword.get(attrs, :player_name, "adam"),
      started_at: Keyword.get(attrs, :started_at, @base),
      ended_at: Keyword.get(attrs, :ended_at, DateTime.add(@base, 3600))
    })
  end

  defp insert_history(attrs \\ []) do
    Repo.insert!(%TurnHistory{
      game_id: Keyword.get(attrs, :game_id, "11111"),
      player_name: Keyword.get(attrs, :player_name, "adam"),
      started: Keyword.get(attrs, :started, @base),
      ended: Keyword.get(attrs, :ended, DateTime.add(@base, 3600))
    })
  end

  describe "list_turns/1" do
    test "returns empty list when no turns exist for the game" do
      assert Turns.list_turns("11111") == []
    end

    test "returns turns for the given game_id" do
      insert_turn()
      [turn] = Turns.list_turns("11111")
      assert turn.game_id == "11111"
      assert turn.player_name == "adam"
    end

    test "does not return turns belonging to other games" do
      insert_turn(game_id: "99999")
      assert Turns.list_turns("11111") == []
    end

    test "returns multiple turns ordered newest first by started_at" do
      second = DateTime.add(@base, 3600)
      third = DateTime.add(@base, 7200)

      insert_turn(player_name: "charlie", started_at: third, ended_at: nil)
      insert_turn(player_name: "adam", started_at: @base, ended_at: second)
      insert_turn(player_name: "bob", started_at: second, ended_at: third)

      names = Turns.list_turns("11111") |> Enum.map(& &1.player_name)
      assert names == ["charlie", "bob", "adam"]
    end

    test "returns all turn fields" do
      reminded = DateTime.add(@base, 1800)

      Repo.insert!(%Turn{
        game_id: "11111",
        player_name: "adam",
        started_at: @base,
        ended_at: DateTime.add(@base, 3600),
        reminded: reminded,
        reminders: 2,
        moving_announced: true
      })

      [turn] = Turns.list_turns("11111")
      assert turn.reminded == reminded
      assert turn.reminders == 2
      assert turn.moving_announced == true
    end
  end

  describe "get_open_turn/1" do
    test "returns nil when no turns exist" do
      assert Turns.get_open_turn("11111") == nil
    end

    test "returns nil when all turns are closed" do
      insert_turn()
      assert Turns.get_open_turn("11111") == nil
    end

    test "returns the open turn" do
      insert_turn(ended_at: nil)
      turn = Turns.get_open_turn("11111")
      assert turn.player_name == "adam"
      assert turn.ended_at == nil
    end

    test "does not return open turns for other games" do
      insert_turn(game_id: "99999", ended_at: nil)
      assert Turns.get_open_turn("11111") == nil
    end

    test "returns the most recent open turn when multiple exist" do
      earlier = DateTime.add(@base, -3600)
      insert_turn(player_name: "adam", started_at: earlier, ended_at: nil)
      insert_turn(player_name: "bob", started_at: @base, ended_at: nil)

      assert Turns.get_open_turn("11111").player_name == "bob"
    end
  end

  describe "get_last_closed_turn/1" do
    test "returns nil when no turns exist" do
      assert Turns.get_last_closed_turn("11111") == nil
    end

    test "returns nil when only open turns exist" do
      insert_turn(ended_at: nil)
      assert Turns.get_last_closed_turn("11111") == nil
    end

    test "returns the most recently closed turn" do
      second = DateTime.add(@base, 3600)
      insert_turn(player_name: "adam", started_at: @base, ended_at: second)
      insert_turn(player_name: "bob", started_at: second, ended_at: DateTime.add(second, 3600))

      assert Turns.get_last_closed_turn("11111").player_name == "bob"
    end

    test "does not return closed turns from other games" do
      insert_turn(game_id: "99999", ended_at: DateTime.add(@base, 3600))
      assert Turns.get_last_closed_turn("11111") == nil
    end
  end

  describe "finish_turn/1" do
    test "sets ended_at on the given turn in the DB" do
      turn = insert_turn(ended_at: nil)
      {:ok, finished} = Turns.finish_turn(turn)
      assert finished.ended_at != nil
      assert Repo.get!(Turn, turn.id).ended_at != nil
    end

    test "returns the updated struct with ended_at populated" do
      turn = insert_turn(ended_at: nil)
      {:ok, finished} = Turns.finish_turn(turn)
      assert finished.player_name == turn.player_name
      assert finished.started_at == turn.started_at
    end

    test "does not affect other turns" do
      other = insert_turn(game_id: "22222", ended_at: nil)
      turn = insert_turn(ended_at: nil)
      Turns.finish_turn(turn)
      assert Repo.get!(Turn, other.id).ended_at == nil
    end
  end

  describe "start_turn/2" do
    test "inserts a new open turn for the player" do
      {:ok, turn} = Turns.start_turn("11111", "adam")
      assert turn.game_id == "11111"
      assert turn.player_name == "adam"
      assert turn.ended_at == nil
    end

    test "does not close any existing open turn" do
      existing = insert_turn(ended_at: nil)
      Turns.start_turn("11111", "bob")
      assert Repo.get!(Turn, existing.id).ended_at == nil
    end
  end

  describe "record_turn_start/2" do
    test "inserts a new open turn for the player" do
      {:ok, turn} = Turns.record_turn_start("11111", "adam")
      assert turn.game_id == "11111"
      assert turn.player_name == "adam"
      assert turn.ended_at == nil
    end

    test "closes any existing open turn before opening the new one" do
      insert_turn(player_name: "adam", ended_at: nil)
      Turns.record_turn_start("11111", "bob")

      [bob, adam] = Turns.list_turns("11111")
      assert bob.player_name == "bob"
      assert bob.ended_at == nil
      assert adam.player_name == "adam"
      assert adam.ended_at != nil
    end

    test "does not close turns belonging to other games" do
      insert_turn(game_id: "22222", player_name: "adam", ended_at: nil)
      Turns.record_turn_start("11111", "bob")

      assert Turns.get_open_turn("22222").player_name == "adam"
    end
  end

  describe "round_info/1" do
    test "returns all-zero/empty result when no turns exist" do
      result = Turns.round_info("11111")

      assert result.current_round == 0
      assert result.turn_number_within_round == 0
      assert result.overall_turn_number == 0
      assert result.seat_number == %{}
      assert result.new_round_starting? == false
      assert result.turn_counts == %{}
    end

    test "single player, single turn" do
      insert_turn(player_name: "adam", started_at: @base, ended_at: nil)
      result = Turns.round_info("11111")

      assert result.current_round == 1
      assert result.turn_number_within_round == 1
      assert result.overall_turn_number == 1
      assert result.seat_number == %{"adam" => 1}
      assert result.new_round_starting? == true
      assert result.turn_counts == %{"adam" => 1}
    end

    test "turn_number_within_round counts players at the max, not all players" do
      t1 = @base
      t2 = DateTime.add(@base, 100)
      t3 = DateTime.add(@base, 200)
      t4 = DateTime.add(@base, 300)
      t5 = DateTime.add(@base, 400)

      # Round 1: adam, bob, charlie all completed
      insert_turn(player_name: "adam", started_at: t1, ended_at: t2)
      insert_turn(player_name: "bob", started_at: t2, ended_at: t3)
      insert_turn(player_name: "charlie", started_at: t3, ended_at: t4)
      # Round 2: adam went, now it's bob's turn (open)
      insert_turn(player_name: "adam", started_at: t4, ended_at: t5)
      insert_turn(player_name: "bob", started_at: t5, ended_at: nil)

      result = Turns.round_info("11111")

      assert result.current_round == 2
      assert result.turn_number_within_round == 2
      assert result.overall_turn_number == 5
      assert result.new_round_starting? == false
    end

    test "new_round_starting? is true when exactly one player is at the max" do
      t1 = @base
      t2 = DateTime.add(@base, 100)
      t3 = DateTime.add(@base, 200)
      t4 = DateTime.add(@base, 300)

      insert_turn(player_name: "adam", started_at: t1, ended_at: t2)
      insert_turn(player_name: "bob", started_at: t2, ended_at: t3)
      insert_turn(player_name: "charlie", started_at: t3, ended_at: t4)
      # Round 2: only adam has started
      insert_turn(player_name: "adam", started_at: t4, ended_at: nil)

      result = Turns.round_info("11111")

      assert result.current_round == 2
      assert result.turn_number_within_round == 1
      assert result.new_round_starting? == true
    end

    test "seat_number reflects chronological order of first turns" do
      t1 = @base
      t2 = DateTime.add(@base, 100)
      t3 = DateTime.add(@base, 200)

      # charlie went first, then adam, then bob
      insert_turn(player_name: "charlie", started_at: t1, ended_at: t2)
      insert_turn(player_name: "adam", started_at: t2, ended_at: t3)
      insert_turn(player_name: "bob", started_at: t3, ended_at: nil)

      result = Turns.round_info("11111")

      assert result.seat_number == %{"charlie" => 1, "adam" => 2, "bob" => 3}
    end

    test "overall_turn_number is the sum of all turn counts" do
      t1 = @base
      t2 = DateTime.add(@base, 100)
      t3 = DateTime.add(@base, 200)
      t4 = DateTime.add(@base, 300)
      t5 = DateTime.add(@base, 400)
      t6 = DateTime.add(@base, 500)

      insert_turn(player_name: "adam", started_at: t1, ended_at: t2)
      insert_turn(player_name: "bob", started_at: t2, ended_at: t3)
      insert_turn(player_name: "adam", started_at: t3, ended_at: t4)
      insert_turn(player_name: "bob", started_at: t4, ended_at: t5)
      insert_turn(player_name: "adam", started_at: t5, ended_at: t6)

      result = Turns.round_info("11111")

      assert result.overall_turn_number == 5
      assert result.current_round == 3
      assert result.turn_number_within_round == 1
    end

    test "does not include turns from other games" do
      insert_turn(game_id: "99999", player_name: "intruder", started_at: @base, ended_at: nil)
      insert_turn(player_name: "adam", started_at: @base, ended_at: nil)

      result = Turns.round_info("11111")

      assert result.turn_counts == %{"adam" => 1}
      refute Map.has_key?(result.seat_number, "intruder")
    end
  end

  describe "backfill_from_turn_history/1" do
    test "inserts a LiveGameState.Turn for every TurnHistory record" do
      insert_history(player_name: "adam", started: @base, ended: DateTime.add(@base, 3600))

      insert_history(
        player_name: "bob",
        started: DateTime.add(@base, 3600),
        ended: DateTime.add(@base, 7200)
      )

      {count, _} = Turns.backfill_from_turn_history("11111")
      assert count == 2
      assert Repo.aggregate(Turn, :count) == 2
    end

    test "maps started and ended to started_at and ended_at" do
      ended = DateTime.add(@base, 3600)
      insert_history(started: @base, ended: ended)
      Turns.backfill_from_turn_history("11111")

      [turn] = Turns.list_turns("11111")
      assert turn.started_at == @base
      assert turn.ended_at == ended
    end

    test "sets reminder fields to defaults" do
      insert_history()
      Turns.backfill_from_turn_history("11111")

      [turn] = Turns.list_turns("11111")
      assert turn.reminders == 0
      assert turn.moving_announced == false
      assert turn.reminded == nil
    end

    test "only inserts records for the given game_id" do
      insert_history(game_id: "11111")
      insert_history(game_id: "22222")

      Turns.backfill_from_turn_history("11111")
      assert Repo.aggregate(Turn, :count) == 1
    end

    test "returns {0, nil} when no history exists" do
      assert {0, nil} = Turns.backfill_from_turn_history("11111")
    end
  end
end
