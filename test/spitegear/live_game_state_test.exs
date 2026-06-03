defmodule Spitegear.LiveGameStateTest do
  use Spitegear.DataCase, async: true

  alias Spitegear.LiveGameState
  alias Spitegear.LiveGameState.Turn
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

  describe "new/1" do
    test "returns a struct with the given game_id" do
      state = LiveGameState.new("11111")
      assert state.game_id == "11111"
    end

    test "current_turn is nil when no open turn exists" do
      assert LiveGameState.new("11111").current_turn == nil
    end

    test "current_turn is the open turn for the game" do
      insert_turn(player_name: "adam", ended_at: nil)
      assert LiveGameState.new("11111").current_turn.player_name == "adam"
    end

    test "prev_turn is nil when no closed turn exists" do
      assert LiveGameState.new("11111").prev_turn == nil
    end

    test "prev_turn is the most recently closed turn" do
      insert_turn(player_name: "adam", started_at: @base, ended_at: DateTime.add(@base, 3600))
      insert_turn(player_name: "bob", started_at: DateTime.add(@base, 3600), ended_at: nil)
      assert LiveGameState.new("11111").prev_turn.player_name == "adam"
    end
  end

  describe "load_recent_turns/1" do
    test "hydrates current_turn from the open turn in the DB" do
      insert_turn(player_name: "adam", ended_at: nil)
      state = %LiveGameState{game_id: "11111"} |> LiveGameState.load_recent_turns()
      assert state.current_turn.player_name == "adam"
    end

    test "hydrates prev_turn from the most recently closed turn" do
      insert_turn(player_name: "adam", started_at: @base, ended_at: DateTime.add(@base, 3600))
      state = %LiveGameState{game_id: "11111"} |> LiveGameState.load_recent_turns()
      assert state.prev_turn.player_name == "adam"
    end

    test "sets current_turn to nil when no open turn exists" do
      state = %LiveGameState{game_id: "11111"} |> LiveGameState.load_recent_turns()
      assert state.current_turn == nil
    end

    test "sets prev_turn to nil when no closed turn exists" do
      state = %LiveGameState{game_id: "11111"} |> LiveGameState.load_recent_turns()
      assert state.prev_turn == nil
    end

    test "preserves other fields on the struct" do
      state = %LiveGameState{game_id: "11111"} |> LiveGameState.load_recent_turns()
      assert state.game_id == "11111"
    end

    test "does not cross game_id boundaries" do
      insert_turn(game_id: "99999", player_name: "adam", ended_at: nil)
      state = %LiveGameState{game_id: "11111"} |> LiveGameState.load_recent_turns()
      assert state.current_turn == nil
    end
  end
end
