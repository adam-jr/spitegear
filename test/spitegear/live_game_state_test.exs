defmodule Spitegear.LiveGameStateTest do
  use ExUnit.Case, async: true

  alias Spitegear.LiveGameState

  doctest Spitegear.LiveGameState

  describe "new_activity?/1" do
    test "false on a fresh struct with no turn data" do
      refute LiveGameState.new_activity?(LiveGameState.new("42"))
    end

    test "false when prev_poll_latest_turn is nil (first successful fetch)" do
      state = %LiveGameState{
        game_id: "42",
        latest_turn: %{"turnid" => "1"},
        prev_poll_latest_turn: nil
      }

      refute LiveGameState.new_activity?(state)
    end

    test "false when latest_turn is nil (fetch failed)" do
      state = %LiveGameState{
        game_id: "42",
        latest_turn: nil,
        prev_poll_latest_turn: %{"turnid" => "1"}
      }

      refute LiveGameState.new_activity?(state)
    end

    test "false when turn ID is unchanged between polls" do
      state = %LiveGameState{
        game_id: "42",
        latest_turn: %{"turnid" => "5"},
        prev_poll_latest_turn: %{"turnid" => "5"}
      }

      refute LiveGameState.new_activity?(state)
    end

    test "true when turn ID has advanced" do
      state = %LiveGameState{
        game_id: "42",
        latest_turn: %{"turnid" => "6"},
        prev_poll_latest_turn: %{"turnid" => "5"}
      }

      assert LiveGameState.new_activity?(state)
    end
  end
end
