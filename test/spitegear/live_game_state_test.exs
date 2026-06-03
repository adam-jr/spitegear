defmodule Spitegear.LiveGameStateTest do
  use Spitegear.DataCase, async: true

  alias Spitegear.GameDeath
  alias Spitegear.LiveGameState
  alias Spitegear.Repo
  alias Spitegear.TurnHistory

  doctest Spitegear.LiveGameState

  @game_id "11111"
  @base ~U[2024-01-01 00:00:00Z]

  defp insert_turn(player, offset_seconds) do
    started = DateTime.add(@base, offset_seconds)
    ended = DateTime.add(@base, offset_seconds + 599)

    Repo.insert!(%TurnHistory{
      game_id: @game_id,
      player_name: player,
      started: started,
      ended: ended
    })
  end

  describe "load_dead_players/1" do
    test "leaves dead_players empty when no deaths recorded" do
      state = LiveGameState.new(@game_id) |> LiveGameState.load_dead_players()
      assert state.dead_players == []
    end

    test "populates dead_players from the DB" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      Repo.insert!(%GameDeath{game_id: @game_id, player_name: "bob", eliminated_at: now})
      Repo.insert!(%GameDeath{game_id: @game_id, player_name: "carol", eliminated_at: now})

      state = LiveGameState.new(@game_id) |> LiveGameState.load_dead_players()
      assert Enum.sort(Enum.map(state.dead_players, & &1.name)) == ["bob", "carol"]
    end

    test "does not load deaths from other games" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      Repo.insert!(%GameDeath{game_id: "99999", player_name: "bob", eliminated_at: now})

      state = LiveGameState.new(@game_id) |> LiveGameState.load_dead_players()
      assert state.dead_players == []
    end
  end

  describe "load_last_round/1" do
    test "returns 0 with no history and no active turn" do
      state = LiveGameState.new(@game_id) |> LiveGameState.load_last_round()
      assert state.last_round == 0
    end

    test "reflects DB-complete rounds when no active turn" do
      insert_turn("adam", 0)
      insert_turn("bob", 600)
      insert_turn("adam", 1200)

      state = LiveGameState.new(@game_id) |> LiveGameState.load_last_round()
      assert state.last_round == 1
    end
  end

  describe "completed_rounds/2" do
    test "returns 0 with no history and no current player" do
      assert LiveGameState.completed_rounds(@game_id, nil) == 0
    end

    test "returns 0 with no history even if a current player exists" do
      assert LiveGameState.completed_rounds(@game_id, "adam") == 0
    end

    test "returns 0 when current player has not yet been in the in-progress round" do
      insert_turn("adam", 0)
      insert_turn("bob", 600)

      assert LiveGameState.completed_rounds(@game_id, "carol") == 0
    end

    test "detects round completion via current player" do
      # DB has [adam, bob, carol] — no repeat yet, so DB alone returns 0
      insert_turn("adam", 0)
      insert_turn("bob", 600)
      insert_turn("carol", 1200)

      # adam just started their turn → they were already in the round → round 1 complete
      assert LiveGameState.completed_rounds(@game_id, "adam") == 1
    end

    test "current player starting a new round does not inflate the count" do
      insert_turn("adam", 0)
      insert_turn("bob", 600)
      insert_turn("carol", 1200)
      insert_turn("adam", 1800)

      # bob just started → bob was NOT yet in the in-progress round [adam]
      assert LiveGameState.completed_rounds(@game_id, "bob") == 1
    end

    test "counts multiple complete rounds plus live round detection" do
      insert_turn("adam", 0)
      insert_turn("bob", 600)
      insert_turn("carol", 1200)
      insert_turn("adam", 1800)
      insert_turn("bob", 2400)
      insert_turn("carol", 3000)

      # adam just started → adam is in the current in-progress round → round 2 complete
      assert LiveGameState.completed_rounds(@game_id, "adam") == 2
    end

    test "nil current player falls back to DB-only count" do
      insert_turn("adam", 0)
      insert_turn("bob", 600)
      insert_turn("adam", 1200)

      assert LiveGameState.completed_rounds(@game_id, nil) == 1
    end
  end
end
