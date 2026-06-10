defmodule Spitegear.LiveGameStateTest do
  use Spitegear.DataCase, async: true

  alias Spitegear.LiveGameState
  alias Spitegear.LiveGameState.Turn
  alias Spitegear.LiveGameState.ViewScreen
  alias Spitegear.LiveGameState.WargearHistoryApiResponseDb
  alias Spitegear.LiveGameState.WargearViewScreenDb
  alias Spitegear.Repo
  alias Spitegear.Wargear.HTTP.ViewScreen, as: HTTPViewScreen

  @base ~U[2024-01-01 12:00:00Z]

  defp player(name), do: %{name: name, slack_name: "@#{name}", color: nil}

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

    test "sets nil/defaults for all fields when DB is empty" do
      state = blank_state() |> LiveGameState.hydrate()
      assert state.current_turn == nil
      assert state.current_view_screen == nil
      assert state.current_api_response == nil
    end
  end

  describe "record_history_response/2" do
    test "inserts on first fetch and sets current_api_response and history_changed: true" do
      state = blank_state() |> LiveGameState.record_history_response(%{"turnid" => "1"})
      assert state.current_api_response.turn_data["turnid"] == "1"
      assert state.prev_api_response == nil
      assert state.history_changed == true
    end

    test "shifts current to prev when turnid changes" do
      state =
        blank_state()
        |> LiveGameState.record_history_response(%{"turnid" => "1"})
        |> LiveGameState.record_history_response(%{"turnid" => "2"})

      assert state.current_api_response.turn_data["turnid"] == "2"
      assert state.prev_api_response.turn_data["turnid"] == "1"
      assert state.history_changed == true
    end

    test "sets history_changed: false when turnid has not changed" do
      state = blank_state() |> LiveGameState.record_history_response(%{"turnid" => "1"})
      state2 = LiveGameState.record_history_response(state, %{"turnid" => "1"})
      assert state2.history_changed == false
      assert state2.current_api_response.turn_data["turnid"] == "1"
    end
  end

  describe "record_changed_view_screen_db/2" do
    test "sets view_screen_changed: true and updates current/prev on first call" do
      state = blank_state() |> LiveGameState.record_changed_view_screen_db(build_view_screen())
      assert state.view_screen_changed == true
      assert %ViewScreen{} = state.current_view_screen
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

      vs = %ViewScreen{
        game_id: "11111",
        current_player_name: "adam",
        players: [],
        eliminated: [],
        winners: [],
        fogged?: false
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

      vs = %ViewScreen{
        game_id: "11111",
        current_player_name: "bob",
        players: [],
        eliminated: [],
        winners: [],
        fogged?: false
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
      vs = %ViewScreen{
        game_id: "11111",
        current_player_name: "adam",
        players: [],
        eliminated: [],
        winners: [],
        fogged?: false
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
      state = %LiveGameState{game_id: "11111", turn_advanced: false}
      assert LiveGameState.announce_next_round(state) == state
    end

    test "no-op when new_round_starting? is false" do
      # adam and bob both on their first turn — no one is ahead, no new round starting
      insert_turn(player_name: "adam", started_at: @base, ended_at: DateTime.add(@base, 3600))

      insert_turn(
        player_name: "bob",
        started_at: DateTime.add(@base, 3600),
        ended_at: DateTime.add(@base, 7200)
      )

      state = %LiveGameState{game_id: "11111", turn_advanced: true}
      assert LiveGameState.announce_next_round(state) == state
    end

    test "publishes message when new round is starting" do
      Phoenix.PubSub.subscribe(Spitegear.PubSub, "slack_messages")

      # adam completes two turns, bob one — adam alone is at max_played_round 2
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

      vs = %ViewScreen{
        game_id: "11111",
        game_name: "Test Game",
        players: [],
        eliminated: [],
        winners: [],
        fogged?: false
      }

      state = %LiveGameState{game_id: "11111", turn_advanced: true, current_view_screen: vs}
      assert LiveGameState.announce_next_round(state) == state
      assert_receive {:message, :spitegear, _}, 500
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

    test "publishes next-turn message to :spitegear and returns state unchanged" do
      Phoenix.PubSub.subscribe(Spitegear.PubSub, "slack_messages")

      turn = %Turn{game_id: "11111", player_name: "adam", started_at: @base}
      state = %LiveGameState{game_id: "11111", turn_advanced: true, current_turn: turn}
      result = LiveGameState.announce_next_turn(state)

      assert result == state
      assert_receive {:message, :spitegear, _}, 500
    end
  end
end
