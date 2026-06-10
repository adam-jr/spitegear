defmodule Spitegear.LiveGameStateTest do
  use Spitegear.DataCase, async: true

  alias Spitegear.GameDeath
  alias Spitegear.HTML.Player
  alias Spitegear.LiveGameState
  alias Spitegear.LiveGameState.Turn
  alias Spitegear.LiveGameState.ViewScreen
  alias Spitegear.LiveGameState.WargearHistoryApiResponseDb
  alias Spitegear.LiveGameState.WargearViewScreenDb
  alias Spitegear.Repo
  alias Spitegear.Wargear.HTTP.ViewScreen, as: HTTPViewScreen

  @base ~U[2024-01-01 12:00:00Z]

  defp player(name), do: %{name: name, slack_name: "@#{name}", color: nil}

  defp vs_player(name, opts \\ []) do
    %Player{
      name: name,
      slack_name: "@#{name}",
      eliminated?: Keyword.get(opts, :eliminated?, false),
      winner?: Keyword.get(opts, :winner?, false),
      current_turn?: Keyword.get(opts, :current_turn?, false)
    }
  end

  defp view_screen(opts) do
    players = Keyword.get(opts, :players, [])

    %ViewScreen{
      game_id: Keyword.get(opts, :game_id, "11111"),
      game_name: Keyword.get(opts, :game_name, "Test Game"),
      players: players,
      current_player_name: Keyword.get(opts, :current_player_name, nil),
      current_player: Keyword.get(opts, :current_player, nil),
      eliminated: Enum.filter(players, & &1.eliminated?),
      winners: Enum.filter(players, & &1.winner?),
      fogged?: Keyword.get(opts, :fogged?, false)
    }
  end

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

  describe "record_changed_history_response/2" do
    test "inserts on first fetch and sets current_api_response and history_changed: true" do
      state = blank_state() |> LiveGameState.record_changed_history_response(%{"turnid" => "1"})
      assert state.current_api_response.turn_data["turnid"] == "1"
      assert state.prev_api_response == nil
      assert state.history_changed == true
    end

    test "shifts current to prev when turnid changes" do
      state =
        blank_state()
        |> LiveGameState.record_changed_history_response(%{"turnid" => "1"})
        |> LiveGameState.record_changed_history_response(%{"turnid" => "2"})

      assert state.current_api_response.turn_data["turnid"] == "2"
      assert state.prev_api_response.turn_data["turnid"] == "1"
      assert state.history_changed == true
    end

    test "sets history_changed: false when turnid has not changed" do
      state = blank_state() |> LiveGameState.record_changed_history_response(%{"turnid" => "1"})
      state2 = LiveGameState.record_changed_history_response(state, %{"turnid" => "1"})
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

  describe "infer_deaths_from_skip/1" do
    test "no-op when turn_advanced is false" do
      state = %LiveGameState{game_id: "11111", turn_advanced: false}
      assert LiveGameState.infer_deaths_from_skip(state) == state
      assert Repo.aggregate(GameDeath, :count) == 0
    end

    test "no-op when prev_turn is nil" do
      vs = view_screen(players: [vs_player("adam"), vs_player("bob")], current_player_name: "bob")

      state = %LiveGameState{
        game_id: "11111",
        turn_advanced: true,
        prev_turn: nil,
        current_view_screen: vs
      }

      assert LiveGameState.infer_deaths_from_skip(state) == state
      assert Repo.aggregate(GameDeath, :count) == 0
    end

    test "no-op when current_view_screen is nil" do
      prev = %Turn{game_id: "11111", player_name: "adam", started_at: @base}

      state = %LiveGameState{
        game_id: "11111",
        turn_advanced: true,
        prev_turn: prev,
        current_view_screen: nil
      }

      assert LiveGameState.infer_deaths_from_skip(state) == state
    end

    test "no-op when no players are skipped" do
      prev = %Turn{game_id: "11111", player_name: "adam", started_at: @base}
      vs = view_screen(players: [vs_player("adam"), vs_player("bob")], current_player_name: "bob")

      state = %LiveGameState{
        game_id: "11111",
        turn_advanced: true,
        prev_turn: prev,
        current_view_screen: vs
      }

      LiveGameState.infer_deaths_from_skip(state)
      assert Repo.aggregate(GameDeath, :count) == 0
    end

    test "records a death when a player is skipped in turn order" do
      prev = %Turn{game_id: "11111", player_name: "adam", started_at: @base}

      vs =
        view_screen(
          players: [vs_player("adam"), vs_player("charlie"), vs_player("bob")],
          current_player_name: "bob"
        )

      state = %LiveGameState{
        game_id: "11111",
        turn_advanced: true,
        prev_turn: prev,
        current_view_screen: vs
      }

      LiveGameState.infer_deaths_from_skip(state)

      deaths = Repo.all(GameDeath)
      assert length(deaths) == 1
      assert hd(deaths).player_name == "charlie"
    end

    test "does not record a death for players already in game_deaths" do
      Repo.insert!(%GameDeath{game_id: "11111", player_name: "charlie", eliminated_at: @base})
      prev = %Turn{game_id: "11111", player_name: "adam", started_at: @base}

      vs =
        view_screen(
          players: [vs_player("adam"), vs_player("charlie"), vs_player("bob")],
          current_player_name: "bob"
        )

      state = %LiveGameState{
        game_id: "11111",
        turn_advanced: true,
        prev_turn: prev,
        current_view_screen: vs
      }

      LiveGameState.infer_deaths_from_skip(state)

      assert Repo.aggregate(GameDeath, :count) == 1
    end

    test "posts to :spitegear_test when not fogged" do
      Phoenix.PubSub.subscribe(Spitegear.PubSub, "slack_messages")
      prev = %Turn{game_id: "11111", player_name: "adam", started_at: @base}

      vs =
        view_screen(
          players: [vs_player("adam"), vs_player("charlie"), vs_player("bob")],
          current_player_name: "bob"
        )

      state = %LiveGameState{
        game_id: "11111",
        turn_advanced: true,
        prev_turn: prev,
        current_view_screen: vs
      }

      LiveGameState.infer_deaths_from_skip(state)

      assert_receive {:message, :spitegear_test, _}, 500
    end

    test "does not post when fogged" do
      Phoenix.PubSub.subscribe(Spitegear.PubSub, "slack_messages")
      prev = %Turn{game_id: "11111", player_name: "adam", started_at: @base}

      vs =
        view_screen(
          players: [vs_player("adam"), vs_player("charlie"), vs_player("bob")],
          current_player_name: "bob",
          fogged?: true
        )

      state = %LiveGameState{
        game_id: "11111",
        turn_advanced: true,
        prev_turn: prev,
        current_view_screen: vs
      }

      LiveGameState.infer_deaths_from_skip(state)

      refute_receive {:message, :spitegear_test, _}, 200
    end
  end

  describe "detect_eliminations/1" do
    test "no-op when view_screen_changed is false" do
      state = %LiveGameState{game_id: "11111", view_screen_changed: false}
      assert LiveGameState.detect_eliminations(state) == state
      assert Repo.aggregate(GameDeath, :count) == 0
    end

    test "no-op when current_view_screen is nil" do
      state = %LiveGameState{
        game_id: "11111",
        view_screen_changed: true,
        current_view_screen: nil
      }

      assert LiveGameState.detect_eliminations(state) == state
    end

    test "no-op when eliminated list is empty" do
      vs = view_screen(players: [vs_player("adam"), vs_player("bob")])
      state = %LiveGameState{game_id: "11111", view_screen_changed: true, current_view_screen: vs}
      LiveGameState.detect_eliminations(state)
      assert Repo.aggregate(GameDeath, :count) == 0
    end

    test "records a death for a newly eliminated player" do
      vs = view_screen(players: [vs_player("adam", eliminated?: true), vs_player("bob")])
      state = %LiveGameState{game_id: "11111", view_screen_changed: true, current_view_screen: vs}
      LiveGameState.detect_eliminations(state)

      deaths = Repo.all(GameDeath)
      assert length(deaths) == 1
      assert hd(deaths).player_name == "adam"
    end

    test "does not re-record a player already in game_deaths" do
      Repo.insert!(%GameDeath{game_id: "11111", player_name: "adam", eliminated_at: @base})
      vs = view_screen(players: [vs_player("adam", eliminated?: true), vs_player("bob")])
      state = %LiveGameState{game_id: "11111", view_screen_changed: true, current_view_screen: vs}
      LiveGameState.detect_eliminations(state)

      assert Repo.aggregate(GameDeath, :count) == 1
    end

    test "posts to :spitegear_test when not fogged" do
      Phoenix.PubSub.subscribe(Spitegear.PubSub, "slack_messages")
      vs = view_screen(players: [vs_player("adam", eliminated?: true), vs_player("bob")])
      state = %LiveGameState{game_id: "11111", view_screen_changed: true, current_view_screen: vs}
      LiveGameState.detect_eliminations(state)

      assert_receive {:message, :spitegear_test, _}, 500
    end

    test "does not post when fogged" do
      Phoenix.PubSub.subscribe(Spitegear.PubSub, "slack_messages")

      vs =
        view_screen(
          players: [vs_player("adam", eliminated?: true), vs_player("bob")],
          fogged?: true
        )

      state = %LiveGameState{game_id: "11111", view_screen_changed: true, current_view_screen: vs}
      LiveGameState.detect_eliminations(state)

      refute_receive {:message, :spitegear_test, _}, 200
    end

    test "returns state unchanged" do
      vs = view_screen(players: [vs_player("adam", eliminated?: true)])
      state = %LiveGameState{game_id: "11111", view_screen_changed: true, current_view_screen: vs}
      assert LiveGameState.detect_eliminations(state) == state
    end
  end

  describe "announce_winners/1" do
    test "no-op when view_screen_changed is false" do
      state = %LiveGameState{game_id: "11111", view_screen_changed: false}
      assert LiveGameState.announce_winners(state) == state
    end

    test "no-op when current_view_screen is nil" do
      state = %LiveGameState{
        game_id: "11111",
        view_screen_changed: true,
        current_view_screen: nil
      }

      assert LiveGameState.announce_winners(state) == state
    end

    test "no-op when winners list is empty" do
      vs = view_screen(players: [vs_player("adam"), vs_player("bob")])
      state = %LiveGameState{game_id: "11111", view_screen_changed: true, current_view_screen: vs}
      assert LiveGameState.announce_winners(state) == state
    end

    test "publishes winner blocks to :spitegear when winners present" do
      Phoenix.PubSub.subscribe(Spitegear.PubSub, "slack_messages")

      vs =
        view_screen(
          players: [vs_player("adam", winner?: true), vs_player("bob")],
          game_name: "Test Game"
        )

      state = %LiveGameState{game_id: "11111", view_screen_changed: true, current_view_screen: vs}

      LiveGameState.announce_winners(state)

      assert_receive {:message, :spitegear, _}, 500
    end

    test "returns state unchanged" do
      vs = view_screen(players: [vs_player("adam", winner?: true)])
      state = %LiveGameState{game_id: "11111", view_screen_changed: true, current_view_screen: vs}
      result = LiveGameState.announce_winners(state)
      assert result == state
    end
  end
end
