defmodule Spitegear.LiveGameStateTest do
  use Spitegear.DataCase, async: true

  alias Spitegear.GameDeath
  alias Spitegear.HTML.Player
  alias Spitegear.LiveGameState
  alias Spitegear.Repo
  alias Spitegear.Turn
  alias Spitegear.TurnHistory
  alias Spitegear.Wargear.HTTP.ViewScreen

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

  defp build_turn(player_name) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %Turn{
      game_id: @game_id,
      player: %{name: player_name},
      player_name: player_name,
      started: now,
      reminded: now,
      reminders: 0
    }
  end

  defp build_view_screen(current_player_name, all_player_names, opts \\ []) do
    players =
      Enum.map(all_player_names, fn name ->
        %Player{
          name: name,
          eliminated?: false,
          winner?: false,
          current_turn?: name == current_player_name
        }
      end)

    %ViewScreen{
      game_id: @game_id,
      game_name: "Test Game",
      current_player: Enum.find(players, &(&1.name == current_player_name)),
      players: players,
      eliminated: [],
      winners: [],
      fogged?: Keyword.get(opts, :fogged?, false)
    }
  end

  describe "reset_view_screen_poll/2" do
    test "sets last_turn_id and resets poll tracking to initial values" do
      state = LiveGameState.new(@game_id)
      updated = LiveGameState.reset_view_screen_poll(state, "turn_99")

      assert updated.last_turn_id == "turn_99"
      assert updated.view_screen_timer == nil
      assert updated.view_screen_polls_remaining == 10
    end

    test "overwrites an existing last_turn_id" do
      state = %{LiveGameState.new(@game_id) | last_turn_id: "old_turn"}
      updated = LiveGameState.reset_view_screen_poll(state, "new_turn")

      assert updated.last_turn_id == "new_turn"
    end

    test "preserves all other fields" do
      state = %{LiveGameState.new(@game_id) | status: :in_progress, last_round: 3}
      updated = LiveGameState.reset_view_screen_poll(state, "t1")

      assert updated.status == :in_progress
      assert updated.last_round == 3
      assert updated.game_id == @game_id
    end
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

  describe "finish_current_turn/1" do
    test "no-op when current_turn is nil" do
      state = LiveGameState.new(@game_id)
      result = LiveGameState.finish_current_turn(state)

      assert result == state
      assert Repo.aggregate(TurnHistory, :count) == 0
    end

    test "records the current turn to turn_history and returns state unchanged" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      turn = %Turn{
        game_id: @game_id,
        player: %{name: "adam"},
        player_name: "adam",
        started: now,
        reminded: now,
        reminders: 0
      }

      state = %{LiveGameState.new(@game_id) | current_turn: turn}

      result = LiveGameState.finish_current_turn(state)

      assert result.current_turn == turn
      assert Repo.aggregate(TurnHistory, :count) == 1
    end
  end

  describe "infer_deaths_from_skip/1" do
    test "no-op when current_turn is nil" do
      state = %{
        LiveGameState.new(@game_id)
        | view_screen: build_view_screen("bob", ["adam", "bob"])
      }

      result = LiveGameState.infer_deaths_from_skip(state)

      assert result.dead_players == []
    end

    test "no-op when no players are skipped" do
      state = %{
        LiveGameState.new(@game_id)
        | current_turn: build_turn("adam"),
          view_screen: build_view_screen("bob", ["adam", "bob"]),
          dead_players: []
      }

      result = LiveGameState.infer_deaths_from_skip(state)
      assert result.dead_players == []
    end

    test "records skipped players as inferred deaths" do
      state = %{
        LiveGameState.new(@game_id)
        | current_turn: build_turn("adam"),
          view_screen: build_view_screen("carol", ["adam", "bob", "carol"]),
          dead_players: []
      }

      result = LiveGameState.infer_deaths_from_skip(state)

      assert length(result.dead_players) == 1
      assert hd(result.dead_players).name == "bob"
      assert Repo.aggregate(GameDeath, :count) == 1
    end

    test "skips players already in dead_players" do
      state = %{
        LiveGameState.new(@game_id)
        | current_turn: build_turn("adam"),
          view_screen: build_view_screen("carol", ["adam", "carol"]),
          dead_players: [%{name: "bob"}]
      }

      result = LiveGameState.infer_deaths_from_skip(state)
      assert result.dead_players == [%{name: "bob"}]
    end
  end

  describe "update_rounds/1" do
    test "no change when no history" do
      state = %{
        LiveGameState.new(@game_id)
        | view_screen: build_view_screen("adam", ["adam", "bob"]),
          last_round: 0
      }

      result = LiveGameState.update_rounds(state)
      assert result.last_round == 0
    end

    test "increments last_round when current player completes a round" do
      insert_turn("adam", 0)
      insert_turn("bob", 600)

      state = %{
        LiveGameState.new(@game_id)
        | view_screen: build_view_screen("adam", ["adam", "bob"]),
          last_round: 0
      }

      result = LiveGameState.update_rounds(state)
      assert result.last_round == 1
    end

    test "does not re-announce a round already recorded in last_round" do
      insert_turn("adam", 0)
      insert_turn("bob", 600)
      insert_turn("adam", 1200)

      state = %{
        LiveGameState.new(@game_id)
        | view_screen: build_view_screen("bob", ["adam", "bob"]),
          last_round: 1
      }

      result = LiveGameState.update_rounds(state)
      assert result.last_round == 1
    end
  end

  describe "start_new_turn/1" do
    test "creates a Turn record in the DB and updates state" do
      state = %{
        LiveGameState.new(@game_id)
        | view_screen: build_view_screen("adam", ["adam", "bob"]),
          moving_announced: true
      }

      result = LiveGameState.start_new_turn(state)

      assert result.moving_announced == false
      assert result.current_turn.player.name == "adam"
      assert Repo.aggregate(Turn, :count) == 1
    end

    test "sets current_turn player from view_screen.current_player" do
      state = %{
        LiveGameState.new(@game_id)
        | view_screen: build_view_screen("bob", ["adam", "bob"])
      }

      result = LiveGameState.start_new_turn(state)
      assert result.current_turn.player.name == "bob"
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
