defmodule Spitegear.Slack.MessageTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Spitegear.Slack.Message

  describe "text(:round_complete, game_id, round, game_name)" do
    test "includes the completed round number" do
      assert Message.text(:round_complete, "99999", 5, "My Game") =~ "Round 5 complete"
    end

    test "includes the next round number" do
      assert Message.text(:round_complete, "99999", 5, "My Game") =~ "round 6 begins"
    end

    test "includes a link to the game" do
      text = Message.text(:round_complete, "99999", 5, "My Game")
      assert text =~ "99999"
      assert text =~ "My Game"
    end
  end

  describe "text(:turn_stats, stats, game_id, rounds)" do
    test "shows rounds not turns in header" do
      stats = [%{player_name: "adam", count: 5, avg_seconds: 300, fastest_seconds: 100, slowest_seconds: 500}]
      text = Message.text(:turn_stats, stats, "99999", 5)
      assert text =~ "5 rounds"
      refute text =~ "turns"
    end
  end
end
