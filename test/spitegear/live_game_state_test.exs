defmodule Spitegear.LiveGameStateTest do
  use Spitegear.DataCase, async: true

  alias Spitegear.LiveGameState
  alias Spitegear.LiveGameState.Turn
  alias Spitegear.LiveGameState.WargearHistoryApiResponseDb
  alias Spitegear.LiveGameState.WargearViewScreenDb
  alias Spitegear.Repo
  alias Spitegear.Wargear.HTTP.ViewScreen, as: HTTPViewScreen

  @base ~U[2024-01-01 12:00:00Z]

  defp player(name), do: %{name: name, slack_name: "@#{name}"}

  defp insert_turn(attrs) do
    Repo.insert!(%Turn{
      game_id: Keyword.get(attrs, :game_id, "11111"),
      player_name: Keyword.get(attrs, :player_name, "adam"),
      started_at: Keyword.get(attrs, :started_at, @base),
      ended_at: Keyword.get(attrs, :ended_at, nil)
    })
  end

  defp insert_view_screen(attrs) do
    Repo.insert!(%WargearViewScreenDb{
      game_id: Keyword.get(attrs, :game_id, "11111"),
      current_player_name: Keyword.get(attrs, :current_player_name, "adam"),
      players: [],
      eliminated: [],
      winners: [],
      fogged: false,
      inserted_at:
        Keyword.get(attrs, :inserted_at, DateTime.utc_now() |> DateTime.truncate(:second)),
      updated_at:
        Keyword.get(attrs, :updated_at, DateTime.utc_now() |> DateTime.truncate(:second))
    })
  end

  defp insert_history_response(attrs) do
    Repo.insert!(%WargearHistoryApiResponseDb{
      game_id: Keyword.get(attrs, :game_id, "11111"),
      turn_data: Keyword.get(attrs, :turn_data, %{"turnid" => "1"}),
      inserted_at:
        Keyword.get(attrs, :inserted_at, DateTime.utc_now() |> DateTime.truncate(:second)),
      updated_at:
        Keyword.get(attrs, :updated_at, DateTime.utc_now() |> DateTime.truncate(:second))
    })
  end

  defp build_view_screen(attrs \\ []) do
    %HTTPViewScreen{
      game_id: Keyword.get(attrs, :game_id, "11111"),
      game_name: "Test Game",
      board_name: "Classic",
      created: "2024-01-01",
      finished: nil,
      current_player: Keyword.get(attrs, :current_player, player("adam")),
      players: [player("adam"), player("bob")],
      eliminated: [],
      winners: [],
      fogged?: false
    }
  end

  defp blank_state(game_id \\ "11111"), do: %LiveGameState{game_id: game_id}

  describe "new/1" do
    test "returns a struct with the given game_id" do
      assert LiveGameState.new("11111").game_id == "11111"
    end

    test "all fields are nil/default when DB is empty" do
      state = LiveGameState.new("11111")
      assert state.current_turn == nil
      assert state.prev_turn == nil
      assert state.current_view_screen == nil
      assert state.prev_view_screen == nil
      assert state.current_api_response == nil
      assert state.prev_api_response == nil
      assert state.completed_round == 0
    end
  end

  describe "hydrate/1" do
    test "hydrates current_turn from the open turn" do
      insert_turn(player_name: "adam", ended_at: nil)
      state = blank_state() |> LiveGameState.hydrate()
      assert state.current_turn.player_name == "adam"
    end

    test "hydrates prev_turn from the most recently closed turn" do
      insert_turn(player_name: "adam", ended_at: DateTime.add(@base, 3600))
      state = blank_state() |> LiveGameState.hydrate()
      assert state.prev_turn.player_name == "adam"
    end

    test "hydrates current_view_screen from the latest snapshot" do
      insert_view_screen(current_player_name: "adam")
      state = blank_state() |> LiveGameState.hydrate()
      assert state.current_view_screen.current_player_name == "adam"
    end

    test "hydrates prev_view_screen from the second most recent snapshot" do
      insert_view_screen(
        current_player_name: "adam",
        inserted_at: ~U[2024-01-01 00:00:00Z],
        updated_at: ~U[2024-01-01 00:00:00Z]
      )

      insert_view_screen(
        current_player_name: "bob",
        inserted_at: ~U[2024-01-02 00:00:00Z],
        updated_at: ~U[2024-01-02 00:00:00Z]
      )

      state = blank_state() |> LiveGameState.hydrate()
      assert state.prev_view_screen.current_player_name == "adam"
    end

    test "hydrates current_api_response from the latest record" do
      insert_history_response(turn_data: %{"turnid" => "5"})
      state = blank_state() |> LiveGameState.hydrate()
      assert state.current_api_response.turn_data["turnid"] == "5"
    end

    test "hydrates prev_api_response from the second most recent record" do
      insert_history_response(
        turn_data: %{"turnid" => "4"},
        inserted_at: ~U[2024-01-01 00:00:00Z],
        updated_at: ~U[2024-01-01 00:00:00Z]
      )

      insert_history_response(
        turn_data: %{"turnid" => "5"},
        inserted_at: ~U[2024-01-02 00:00:00Z],
        updated_at: ~U[2024-01-02 00:00:00Z]
      )

      state = blank_state() |> LiveGameState.hydrate()
      assert state.prev_api_response.turn_data["turnid"] == "4"
    end

    test "hydrates completed_round from completed turns" do
      insert_turn(player_name: "adam", started_at: @base, ended_at: DateTime.add(@base, 3600))

      insert_turn(
        player_name: "bob",
        started_at: DateTime.add(@base, 3600),
        ended_at: DateTime.add(@base, 7200)
      )

      insert_turn(
        player_name: "adam",
        started_at: DateTime.add(@base, 7200),
        ended_at: DateTime.add(@base, 10_800)
      )

      state = blank_state() |> LiveGameState.hydrate()
      assert state.completed_round == 1
    end

    test "sets nil/defaults for all fields when DB is empty" do
      state = blank_state() |> LiveGameState.hydrate()
      assert state.current_turn == nil
      assert state.current_view_screen == nil
      assert state.current_api_response == nil
      assert state.completed_round == 0
    end
  end

  describe "dispatch_history_response/2" do
    test "inserts on first fetch and sets current_api_response" do
      state = blank_state() |> LiveGameState.dispatch_history_response(%{"turnid" => "1"})
      assert state.current_api_response.turn_data["turnid"] == "1"
      assert state.prev_api_response == nil
    end

    test "shifts current to prev when turnid changes" do
      state =
        blank_state()
        |> LiveGameState.dispatch_history_response(%{"turnid" => "1"})
        |> LiveGameState.dispatch_history_response(%{"turnid" => "2"})

      assert state.current_api_response.turn_data["turnid"] == "2"
      assert state.prev_api_response.turn_data["turnid"] == "1"
    end

    test "returns state unchanged when turnid has not changed" do
      state = blank_state() |> LiveGameState.dispatch_history_response(%{"turnid" => "1"})
      state2 = LiveGameState.dispatch_history_response(state, %{"turnid" => "1"})
      assert state2 == state
    end
  end

  describe "record_changed_view_screen_db/2" do
    test "sets view_screen_changed: true and updates current/prev on first call" do
      state = blank_state() |> LiveGameState.record_changed_view_screen_db(build_view_screen())
      assert state.view_screen_changed == true
      assert %WargearViewScreenDb{} = state.current_view_screen
      assert state.current_view_screen.current_player_name == "adam"
      assert state.prev_view_screen == nil
    end

    test "shifts current to prev when view screen changes" do
      raw_adam = build_view_screen(current_player: player("adam"))
      raw_bob = build_view_screen(current_player: player("bob"))

      state =
        blank_state()
        |> LiveGameState.record_changed_view_screen_db(raw_adam)
        |> LiveGameState.record_changed_view_screen_db(raw_bob)

      assert state.current_view_screen.current_player_name == "bob"
      assert state.prev_view_screen.current_player_name == "adam"
    end

    test "sets view_screen_changed: false when unchanged" do
      raw = build_view_screen()
      state = blank_state() |> LiveGameState.record_changed_view_screen_db(raw)
      state2 = LiveGameState.record_changed_view_screen_db(state, raw)
      assert state2.view_screen_changed == false
      assert Repo.aggregate(WargearViewScreenDb, :count) == 1
    end
  end

  describe "advance_turn/1" do
    test "no-op when view_screen_changed is false" do
      state = %LiveGameState{game_id: "11111", view_screen_changed: false}
      result = LiveGameState.advance_turn(state)
      assert result.turn_advanced == false
      assert Repo.aggregate(Turn, :count) == 0
    end

    test "no-op when current_view_screen is nil" do
      state = %LiveGameState{
        game_id: "11111",
        view_screen_changed: true,
        current_view_screen: nil
      }

      result = LiveGameState.advance_turn(state)
      assert result.turn_advanced == false
    end

    test "no-op when active player is unchanged" do
      open_turn = insert_turn(player_name: "adam", ended_at: nil)

      vs = %WargearViewScreenDb{
        game_id: "11111",
        current_player_name: "adam",
        players: [],
        eliminated: [],
        winners: [],
        fogged: false
      }

      state = %LiveGameState{
        game_id: "11111",
        current_view_screen: vs,
        current_turn: open_turn,
        view_screen_changed: true
      }

      result = LiveGameState.advance_turn(state)
      assert result.turn_advanced == false
      assert Repo.aggregate(Turn, :count) == 1
    end

    test "finishes prev turn and starts new turn when player changes" do
      old_turn = insert_turn(player_name: "adam", ended_at: nil)

      vs = %WargearViewScreenDb{
        game_id: "11111",
        current_player_name: "bob",
        players: [],
        eliminated: [],
        winners: [],
        fogged: false
      }

      state = %LiveGameState{
        game_id: "11111",
        current_view_screen: vs,
        current_turn: old_turn,
        view_screen_changed: true
      }

      result = LiveGameState.advance_turn(state)

      assert result.turn_advanced == true
      assert result.current_turn.player_name == "bob"
      assert result.current_turn.ended_at == nil
      assert result.prev_turn.player_name == "adam"
      assert result.prev_turn.ended_at != nil
      assert Repo.aggregate(Turn, :count) == 2
    end

    test "starts a new turn with no prior turn" do
      vs = %WargearViewScreenDb{
        game_id: "11111",
        current_player_name: "adam",
        players: [],
        eliminated: [],
        winners: [],
        fogged: false
      }

      state = %LiveGameState{game_id: "11111", current_view_screen: vs, view_screen_changed: true}
      result = LiveGameState.advance_turn(state)

      assert result.turn_advanced == true
      assert result.current_turn.player_name == "adam"
      assert result.prev_turn == nil
    end
  end

  describe "announce_next_round/1" do
    test "no-op when turn_advanced is false" do
      state = %LiveGameState{game_id: "11111", turn_advanced: false, completed_round: 0}
      assert LiveGameState.announce_next_round(state).completed_round == 0
    end

    test "no-op when no new round has completed" do
      state = %LiveGameState{game_id: "11111", turn_advanced: true, completed_round: 0}
      assert LiveGameState.announce_next_round(state).completed_round == 0
    end

    test "updates completed_round and publishes message when a round completes" do
      Phoenix.PubSub.subscribe(Spitegear.PubSub, "slack_messages")

      now = DateTime.utc_now() |> DateTime.truncate(:second)
      insert_turn(player_name: "adam", started_at: now, ended_at: DateTime.add(now, 3600))

      insert_turn(
        player_name: "bob",
        started_at: DateTime.add(now, 3600),
        ended_at: DateTime.add(now, 7200)
      )

      insert_turn(
        player_name: "adam",
        started_at: DateTime.add(now, 7200),
        ended_at: DateTime.add(now, 10_800)
      )

      state = %LiveGameState{game_id: "11111", turn_advanced: true, completed_round: 0}
      result = LiveGameState.announce_next_round(state)

      assert result.completed_round == 1
      assert_receive {:message, :spitegear_test, "Round 1 complete in game 11111"}, 500
    end
  end

  describe "announce_next_turn/1" do
    test "no-op when turn_advanced is false" do
      state = %LiveGameState{game_id: "11111", turn_advanced: false}
      assert LiveGameState.announce_next_turn(state) == state
    end

    test "no-op when current_turn is nil" do
      state = %LiveGameState{game_id: "11111", turn_advanced: true, current_turn: nil}
      assert LiveGameState.announce_next_turn(state) == state
    end

    test "publishes next-turn message and returns state unchanged" do
      Phoenix.PubSub.subscribe(Spitegear.PubSub, "slack_messages")

      turn = %Turn{game_id: "11111", player_name: "adam", started_at: @base}
      state = %LiveGameState{game_id: "11111", turn_advanced: true, current_turn: turn}
      result = LiveGameState.announce_next_turn(state)

      assert result == state
      assert_receive {:message, :spitegear_test, "adam's turn in game 11111"}, 500
    end
  end
end
