defmodule Spitegear.LiveGameStateTest do
  use Spitegear.DataCase, async: true

  alias Spitegear.LiveGameState
  alias Spitegear.LiveGameState.Turn
  alias Spitegear.LiveGameState.WargearHistoryApiResponseDb
  alias Spitegear.LiveGameState.WargearViewScreenDb
  alias Spitegear.Repo

  @base ~U[2024-01-01 12:00:00Z]

  defp insert_turn(attrs \\ []) do
    Repo.insert!(%Turn{
      game_id: Keyword.get(attrs, :game_id, "11111"),
      player_name: Keyword.get(attrs, :player_name, "adam"),
      started_at: Keyword.get(attrs, :started_at, @base),
      ended_at: Keyword.get(attrs, :ended_at, nil)
    })
  end

  defp insert_view_screen(attrs \\ []) do
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

  defp insert_history_response(attrs \\ []) do
    Repo.insert!(%WargearHistoryApiResponseDb{
      game_id: Keyword.get(attrs, :game_id, "11111"),
      turn_data: Keyword.get(attrs, :turn_data, %{"turnid" => "1"}),
      inserted_at:
        Keyword.get(attrs, :inserted_at, DateTime.utc_now() |> DateTime.truncate(:second)),
      updated_at:
        Keyword.get(attrs, :updated_at, DateTime.utc_now() |> DateTime.truncate(:second))
    })
  end

  describe "new/1" do
    test "returns a struct with the given game_id" do
      assert LiveGameState.new("11111").game_id == "11111"
    end

    test "all fields are nil when DB is empty" do
      state = LiveGameState.new("11111")
      assert state.current_turn == nil
      assert state.prev_turn == nil
      assert state.current_view_screen == nil
      assert state.prev_view_screen == nil
      assert state.current_history_response == nil
      assert state.prev_history_response == nil
    end
  end

  describe "load_recent_turns/1" do
    test "hydrates current_turn from the open turn" do
      insert_turn(player_name: "adam", ended_at: nil)
      state = %LiveGameState{game_id: "11111"} |> LiveGameState.load_recent_turns()
      assert state.current_turn.player_name == "adam"
    end

    test "hydrates prev_turn from the most recently closed turn" do
      insert_turn(player_name: "adam", ended_at: DateTime.add(@base, 3600))
      state = %LiveGameState{game_id: "11111"} |> LiveGameState.load_recent_turns()
      assert state.prev_turn.player_name == "adam"
    end

    test "hydrates current_view_screen from the latest snapshot" do
      insert_view_screen(current_player_name: "adam")
      state = %LiveGameState{game_id: "11111"} |> LiveGameState.load_recent_turns()
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

      state = %LiveGameState{game_id: "11111"} |> LiveGameState.load_recent_turns()
      assert state.prev_view_screen.current_player_name == "adam"
    end

    test "hydrates current_history_response from the latest record" do
      insert_history_response(turn_data: %{"turnid" => "5"})
      state = %LiveGameState{game_id: "11111"} |> LiveGameState.load_recent_turns()
      assert state.current_history_response.turn_data["turnid"] == "5"
    end

    test "hydrates prev_history_response from the second most recent record" do
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

      state = %LiveGameState{game_id: "11111"} |> LiveGameState.load_recent_turns()
      assert state.prev_history_response.turn_data["turnid"] == "4"
    end

    test "sets nil for all fields when DB is empty" do
      state = %LiveGameState{game_id: "11111"} |> LiveGameState.load_recent_turns()
      assert state.current_turn == nil
      assert state.prev_turn == nil
      assert state.current_view_screen == nil
      assert state.prev_view_screen == nil
      assert state.current_history_response == nil
      assert state.prev_history_response == nil
    end

    test "preserves game_id and does not cross game boundaries" do
      insert_turn(game_id: "99999", ended_at: nil)
      state = %LiveGameState{game_id: "11111"} |> LiveGameState.load_recent_turns()
      assert state.game_id == "11111"
      assert state.current_turn == nil
    end
  end
end
