defmodule Spitegear.GameLog.StatsTest do
  use Spitegear.DataCase, async: true

  alias Spitegear.GameLog.Stats
  alias Spitegear.GameLogEvent
  alias Spitegear.Repo

  @game_id "stats_test_game"

  defp event(attrs) do
    %GameLogEvent{}
    |> GameLogEvent.changeset(
      Map.merge(%{game_id: @game_id, event_type: "started_turn", raw_action: "x"}, attrs)
    )
    |> Repo.insert!()
  end

  describe "net_units_over_time/1" do
    test "returns empty map when no unit-affecting events exist" do
      event(%{log_seq: 1, event_type: "started_turn", raw_action: "Alice started turn"})
      assert %{} == Stats.net_units_over_time(@game_id)
    end

    test "tracks received_units" do
      event(%{
        log_seq: 5,
        event_type: "received_units",
        player: "Alice",
        units: 3,
        raw_action: "x"
      })

      assert %{"Alice" => [%{seq: 5, net_units: 3}]} == Stats.net_units_over_time(@game_id)
    end

    test "tracks received_bonus" do
      event(%{log_seq: 2, event_type: "received_bonus", player: "Bob", units: 7, raw_action: "x"})
      assert %{"Bob" => [%{seq: 2, net_units: 7}]} == Stats.net_units_over_time(@game_id)
    end

    test "tracks factory_produced" do
      event(%{
        log_seq: 4,
        event_type: "factory_produced",
        player: "Alice",
        units: 2,
        raw_action: "x"
      })

      assert %{"Alice" => [%{seq: 4, net_units: 2}]} == Stats.net_units_over_time(@game_id)
    end

    test "tracks traded_cards" do
      event(%{log_seq: 6, event_type: "traded_cards", player: "Alice", units: 4, raw_action: "x"})
      assert %{"Alice" => [%{seq: 6, net_units: 4}]} == Stats.net_units_over_time(@game_id)
    end

    test "captured_reserve_units adds to capturer and deducts from eliminated player" do
      event(%{
        log_seq: 1,
        event_type: "received_units",
        player: "Alice",
        units: 10,
        raw_action: "x"
      })

      event(%{log_seq: 2, event_type: "received_units", player: "Bob", units: 6, raw_action: "x"})

      event(%{
        log_seq: 5,
        event_type: "captured_reserve_units",
        player: "Alice",
        defender: "Bob",
        units: 6,
        raw_action: "x"
      })

      result = Stats.net_units_over_time(@game_id)
      assert [%{seq: 1, net_units: 10}, %{seq: 5, net_units: 16}] == result["Alice"]
      assert [%{seq: 2, net_units: 6}, %{seq: 5, net_units: 0}] == result["Bob"]
    end

    test "captured_reserve_units with nil defender only adds to capturer" do
      event(%{
        log_seq: 1,
        event_type: "received_units",
        player: "Alice",
        units: 10,
        raw_action: "x"
      })

      event(%{
        log_seq: 5,
        event_type: "captured_reserve_units",
        player: "Alice",
        defender: nil,
        units: 6,
        raw_action: "x"
      })

      result = Stats.net_units_over_time(@game_id)
      assert [%{seq: 1, net_units: 10}, %{seq: 5, net_units: 16}] == result["Alice"]
    end

    test "cumulates multiple positive events for the same player" do
      event(%{
        log_seq: 1,
        event_type: "received_units",
        player: "Alice",
        units: 5,
        raw_action: "x"
      })

      event(%{
        log_seq: 3,
        event_type: "received_bonus",
        player: "Alice",
        units: 3,
        raw_action: "x"
      })

      event(%{log_seq: 7, event_type: "traded_cards", player: "Alice", units: 4, raw_action: "x"})

      assert %{
               "Alice" => [
                 %{seq: 1, net_units: 5},
                 %{seq: 3, net_units: 8},
                 %{seq: 7, net_units: 12}
               ]
             } == Stats.net_units_over_time(@game_id)
    end

    test "attacker losses are negative for the attacker" do
      event(%{
        log_seq: 1,
        event_type: "received_units",
        player: "Alice",
        units: 10,
        raw_action: "x"
      })

      event(%{
        log_seq: 5,
        event_type: "attacked",
        player: "Alice",
        defender: "Bob",
        attacker_losses: 2,
        defender_losses: 1,
        raw_action: "x"
      })

      result = Stats.net_units_over_time(@game_id)
      assert [%{seq: 1, net_units: 10}, %{seq: 5, net_units: 8}] == result["Alice"]
    end

    test "defender losses are negative for the defender" do
      event(%{log_seq: 1, event_type: "received_units", player: "Bob", units: 6, raw_action: "x"})

      event(%{
        log_seq: 5,
        event_type: "attacked",
        player: "Alice",
        defender: "Bob",
        attacker_losses: 0,
        defender_losses: 2,
        raw_action: "x"
      })

      result = Stats.net_units_over_time(@game_id)
      assert [%{seq: 1, net_units: 6}, %{seq: 5, net_units: 4}] == result["Bob"]
    end

    test "attacked event generates deltas for both sides independently" do
      event(%{
        log_seq: 3,
        event_type: "attacked",
        player: "Alice",
        defender: "Bob",
        attacker_losses: 1,
        defender_losses: 2,
        raw_action: "x"
      })

      result = Stats.net_units_over_time(@game_id)
      assert [%{seq: 3, net_units: -1}] == result["Alice"]
      assert [%{seq: 3, net_units: -2}] == result["Bob"]
    end

    test "nil losses produce no delta" do
      event(%{
        log_seq: 1,
        event_type: "attacked",
        player: "Alice",
        defender: nil,
        attacker_losses: nil,
        defender_losses: nil,
        raw_action: "x"
      })

      assert %{} == Stats.net_units_over_time(@game_id)
    end

    test "discarded_units are negative" do
      event(%{
        log_seq: 1,
        event_type: "received_units",
        player: "Alice",
        units: 10,
        raw_action: "x"
      })

      event(%{
        log_seq: 4,
        event_type: "discarded_units",
        player: "Alice",
        units: 3,
        raw_action: "x"
      })

      assert %{
               "Alice" => [%{seq: 1, net_units: 10}, %{seq: 4, net_units: 7}]
             } == Stats.net_units_over_time(@game_id)
    end

    test "multiple players tracked independently" do
      event(%{
        log_seq: 1,
        event_type: "received_units",
        player: "Alice",
        units: 5,
        raw_action: "x"
      })

      event(%{log_seq: 2, event_type: "received_units", player: "Bob", units: 3, raw_action: "x"})
      event(%{log_seq: 3, event_type: "traded_cards", player: "Alice", units: 4, raw_action: "x"})

      result = Stats.net_units_over_time(@game_id)
      assert [%{seq: 1, net_units: 5}, %{seq: 3, net_units: 9}] == result["Alice"]
      assert [%{seq: 2, net_units: 3}] == result["Bob"]
    end

    test "factory_destroyed units are negative" do
      event(%{
        log_seq: 1,
        event_type: "received_units",
        player: "Alice",
        units: 10,
        raw_action: "x"
      })

      event(%{
        log_seq: 4,
        event_type: "factory_destroyed",
        player: "Alice",
        units: 3,
        raw_action: "x"
      })

      assert %{
               "Alice" => [%{seq: 1, net_units: 10}, %{seq: 4, net_units: 7}]
             } == Stats.net_units_over_time(@game_id)
    end

    test "returns empty map for unknown game" do
      assert %{} == Stats.net_units_over_time("nonexistent_game_id")
    end
  end

  describe "placement_scores/1" do
    test "returns empty map when no unit events" do
      event(%{log_seq: 1, event_type: "started_turn", raw_action: "Alice started turn"})
      assert %{} == Stats.placement_scores(@game_id)
    end

    test "returns empty map for unknown game" do
      assert %{} == Stats.placement_scores("nonexistent")
    end

    test "score is net_units times duration from setup to last event" do
      event(%{
        log_seq: 1,
        event_type: "placed_units",
        player: "Alice",
        units: 10,
        raw_action: "x"
      })

      event(%{log_seq: 5, event_type: "setup", raw_action: "Initial board setup complete"})
      event(%{log_seq: 15, event_type: "started_turn", raw_action: "started_turn"})
      # Alice: net 10 aggregated at setup seq 5, last_seq = 15
      # score = 10 * (15 - 5) = 100
      assert %{"Alice" => 100} == Stats.placement_scores(@game_id)
    end

    test "score accumulates over multiple post-setup intervals" do
      event(%{log_seq: 5, event_type: "setup", raw_action: "Initial board setup complete"})

      event(%{
        log_seq: 10,
        event_type: "received_units",
        player: "Alice",
        units: 10,
        raw_action: "x"
      })

      event(%{
        log_seq: 20,
        event_type: "received_units",
        player: "Alice",
        units: 5,
        raw_action: "x"
      })

      event(%{log_seq: 30, event_type: "started_turn", raw_action: "started_turn"})
      # score = 10 * (20 - 10) + 15 * (30 - 20) = 100 + 150 = 250
      assert %{"Alice" => 250} == Stats.placement_scores(@game_id)
    end

    test "setup units count from the setup seq onward, not before" do
      event(%{
        log_seq: 1,
        event_type: "placed_units",
        player: "Alice",
        units: 10,
        raw_action: "x"
      })

      event(%{log_seq: 5, event_type: "setup", raw_action: "Initial board setup complete"})

      event(%{
        log_seq: 15,
        event_type: "received_units",
        player: "Alice",
        units: 3,
        raw_action: "x"
      })

      event(%{log_seq: 25, event_type: "started_turn", raw_action: "started_turn"})
      # Alice: net 10 at seq 5, net 13 at seq 15, last_seq = 25
      # score = 10 * (15 - 5) + 13 * (25 - 15) = 100 + 130 = 230
      assert %{"Alice" => 230} == Stats.placement_scores(@game_id)
    end

    test "multiple players scored independently" do
      event(%{log_seq: 5, event_type: "setup", raw_action: "Initial board setup complete"})

      event(%{
        log_seq: 10,
        event_type: "received_units",
        player: "Alice",
        units: 10,
        raw_action: "x"
      })

      event(%{
        log_seq: 11,
        event_type: "received_units",
        player: "Bob",
        units: 6,
        raw_action: "x"
      })

      event(%{log_seq: 20, event_type: "started_turn", raw_action: "started_turn"})
      # last_seq = 20; Alice: 10 * (20 - 10) = 100; Bob: 6 * (20 - 11) = 54
      result = Stats.placement_scores(@game_id)
      assert result["Alice"] == 100
      assert result["Bob"] == 54
    end

    test "unit losses reduce score" do
      event(%{log_seq: 5, event_type: "setup", raw_action: "Initial board setup complete"})

      event(%{
        log_seq: 10,
        event_type: "received_units",
        player: "Alice",
        units: 10,
        raw_action: "x"
      })

      event(%{
        log_seq: 15,
        event_type: "attacked",
        player: "Bob",
        defender: "Alice",
        attacker_losses: 0,
        defender_losses: 4,
        raw_action: "x"
      })

      event(%{log_seq: 20, event_type: "started_turn", raw_action: "started_turn"})
      # Alice: net 10 at seq 10, net 6 at seq 15, last_seq = 20
      # score = 10 * (15 - 10) + 6 * (20 - 15) = 50 + 30 = 80
      assert Stats.placement_scores(@game_id)["Alice"] == 80
    end
  end

  describe "net_units_over_time/1 — setup phase initialization" do
    test "placed_units before setup event count as starting net units" do
      event(%{log_seq: 3, event_type: "placed_units", player: "Alice", units: 5, raw_action: "x"})
      event(%{log_seq: 5, event_type: "placed_units", player: "Alice", units: 3, raw_action: "x"})
      event(%{log_seq: 8, event_type: "setup", raw_action: "Initial board setup complete"})

      event(%{
        log_seq: 12,
        event_type: "received_units",
        player: "Alice",
        units: 2,
        raw_action: "x"
      })

      # Setup placements are aggregated into one starting point at the setup seq
      assert %{
               "Alice" => [
                 %{seq: 8, net_units: 8},
                 %{seq: 12, net_units: 10}
               ]
             } == Stats.net_units_over_time(@game_id)
    end

    test "placed_units before first started_turn count as starting net when no setup event" do
      event(%{log_seq: 2, event_type: "placed_units", player: "Bob", units: 4, raw_action: "x"})

      event(%{
        log_seq: 6,
        event_type: "started_turn",
        player: "Bob",
        raw_action: "Bob started turn"
      })

      event(%{
        log_seq: 10,
        event_type: "received_units",
        player: "Bob",
        units: 3,
        raw_action: "x"
      })

      # Aggregated into one starting point at the started_turn cutoff seq
      assert %{
               "Bob" => [%{seq: 6, net_units: 4}, %{seq: 10, net_units: 7}]
             } == Stats.net_units_over_time(@game_id)
    end

    test "placed_units after setup event are ignored (in-game bonus placements)" do
      event(%{log_seq: 2, event_type: "setup", raw_action: "Initial board setup complete"})
      event(%{log_seq: 5, event_type: "placed_units", player: "Alice", units: 3, raw_action: "x"})

      event(%{
        log_seq: 8,
        event_type: "received_units",
        player: "Alice",
        units: 3,
        raw_action: "x"
      })

      assert %{"Alice" => [%{seq: 8, net_units: 3}]} == Stats.net_units_over_time(@game_id)
    end

    test "Neutral player placements are excluded from setup deltas" do
      event(%{
        log_seq: 2,
        event_type: "placed_units",
        player: "Neutral",
        units: 5,
        raw_action: "x"
      })

      event(%{log_seq: 3, event_type: "placed_units", player: "Alice", units: 6, raw_action: "x"})
      event(%{log_seq: 5, event_type: "setup", raw_action: "Initial board setup complete"})

      result = Stats.net_units_over_time(@game_id)
      assert [%{seq: 5, net_units: 6}] == result["Alice"]
      refute Map.has_key?(result, "Neutral")
    end

    test "multiple players initialized independently from setup placed_units" do
      event(%{log_seq: 1, event_type: "placed_units", player: "Alice", units: 6, raw_action: "x"})
      event(%{log_seq: 2, event_type: "placed_units", player: "Bob", units: 4, raw_action: "x"})
      event(%{log_seq: 3, event_type: "placed_units", player: "Alice", units: 2, raw_action: "x"})
      event(%{log_seq: 5, event_type: "setup", raw_action: "Initial board setup complete"})

      # Each player gets one aggregated starting point at the setup seq
      result = Stats.net_units_over_time(@game_id)
      assert [%{seq: 5, net_units: 8}] == result["Alice"]
      assert [%{seq: 5, net_units: 4}] == result["Bob"]
    end

    test "setup placed_units with nil player or units produce no delta" do
      event(%{log_seq: 1, event_type: "placed_units", player: nil, units: 5, raw_action: "x"})

      event(%{
        log_seq: 2,
        event_type: "placed_units",
        player: "Alice",
        units: nil,
        raw_action: "x"
      })

      event(%{log_seq: 5, event_type: "setup", raw_action: "Initial board setup complete"})

      assert %{} == Stats.net_units_over_time(@game_id)
    end

    test "combat losses after setup are applied from the setup baseline" do
      event(%{
        log_seq: 2,
        event_type: "placed_units",
        player: "Alice",
        units: 10,
        raw_action: "x"
      })

      event(%{log_seq: 3, event_type: "placed_units", player: "Bob", units: 8, raw_action: "x"})
      event(%{log_seq: 5, event_type: "setup", raw_action: "Initial board setup complete"})

      event(%{
        log_seq: 10,
        event_type: "attacked",
        player: "Alice",
        defender: "Bob",
        attacker_losses: 1,
        defender_losses: 3,
        raw_action: "x"
      })

      # Starting point aggregated at setup seq, then combat loss applied after
      result = Stats.net_units_over_time(@game_id)
      assert [%{seq: 5, net_units: 10}, %{seq: 10, net_units: 9}] == result["Alice"]
      assert [%{seq: 5, net_units: 8}, %{seq: 10, net_units: 5}] == result["Bob"]
    end
  end
end
