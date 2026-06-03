defmodule Spitegear.Worker.GamePoller.TurnLogicTest do
  use ExUnit.Case, async: true

  alias Spitegear.HTML.Player
  alias Spitegear.Wargear.HTTP.ViewScreen
  alias Spitegear.Turn
  alias Spitegear.Worker.GamePoller.TurnLogic

  describe "new_turn?/1" do
    test "false when current_player is nil" do
      state = %{view_screen: %ViewScreen{current_player: nil}, current_turn: nil}
      refute TurnLogic.new_turn?(state)
    end

    test "true when no current_turn and current_player exists" do
      state = %{
        view_screen: %ViewScreen{current_player: %Player{name: "adam"}},
        current_turn: nil
      }

      assert TurnLogic.new_turn?(state)
    end

    test "false when current_turn player matches current_player" do
      state = %{
        view_screen: %ViewScreen{current_player: %Player{name: "adam"}},
        current_turn: %Turn{player: %{name: "adam"}}
      }

      refute TurnLogic.new_turn?(state)
    end

    test "true when current_turn player differs from current_player" do
      state = %{
        view_screen: %ViewScreen{current_player: %Player{name: "bob"}},
        current_turn: %Turn{player: %{name: "adam"}}
      }

      assert TurnLogic.new_turn?(state)
    end
  end

  describe "reminder_due?/2" do
    # January (CST = UTC-6): 15:00 UTC = 09:00 CST (waking), 07:00 UTC = 01:00 CST (sleeping)
    @waking_now ~U[2024-01-15 15:00:00Z]
    @sleeping_now ~U[2024-01-15 07:00:00Z]
    @horizon_seconds 3 * 60 * 60

    test "false when current_turn is nil" do
      refute TurnLogic.reminder_due?(%{current_turn: nil}, @waking_now)
    end

    test "false when reminded recently (within horizon), waking hours" do
      reminded = DateTime.add(@waking_now, -@horizon_seconds + 60)
      state = %{current_turn: %Turn{reminded: reminded}}
      refute TurnLogic.reminder_due?(state, @waking_now)
    end

    test "true when beyond horizon and waking hours" do
      reminded = DateTime.add(@waking_now, -@horizon_seconds - 1)
      state = %{current_turn: %Turn{reminded: reminded}}
      assert TurnLogic.reminder_due?(state, @waking_now)
    end

    test "false when beyond horizon but sleeping hours" do
      reminded = DateTime.add(@sleeping_now, -@horizon_seconds - 1)
      state = %{current_turn: %Turn{reminded: reminded}}
      refute TurnLogic.reminder_due?(state, @sleeping_now)
    end

    test "true at exactly the waking-hours boundary (7am Chicago)" do
      # 13:00 UTC = 07:00 CST, exactly on the >= 7 boundary
      boundary_now = ~U[2024-01-15 13:00:00Z]
      reminded = DateTime.add(boundary_now, -@horizon_seconds - 1)
      state = %{current_turn: %Turn{reminded: reminded}}
      assert TurnLogic.reminder_due?(state, boundary_now)
    end

    test "false at midnight Chicago (hour 0, sleeping)" do
      # 06:00 UTC = 00:00 CST
      midnight_now = ~U[2024-01-15 06:00:00Z]
      reminded = DateTime.add(midnight_now, -@horizon_seconds - 1)
      state = %{current_turn: %Turn{reminded: reminded}}
      refute TurnLogic.reminder_due?(state, midnight_now)
    end
  end

  describe "skipped_players/4" do
    @players [%{name: "alice"}, %{name: "bob"}, %{name: "carol"}, %{name: "dave"}]
    @n 4

    test "returns [] when prev_idx is nil" do
      assert TurnLogic.skipped_players(@players, @n, nil, 1) == []
    end

    test "returns [] when curr_idx is nil" do
      assert TurnLogic.skipped_players(@players, @n, 0, nil) == []
    end

    test "returns [] when n < 2" do
      assert TurnLogic.skipped_players([%{name: "alice"}], 1, 0, 0) == []
    end

    test "returns [] when next player is adjacent — no skip" do
      # alice(0) -> bob(1): no one between them
      assert TurnLogic.skipped_players(@players, @n, 0, 1) == []
    end

    test "returns [] on normal wrap-around — last to first" do
      # dave(3) -> alice(0): standard end-of-round progression
      assert TurnLogic.skipped_players(@players, @n, 3, 0) == []
    end

    test "returns one skipped player" do
      # alice(0) -> carol(2): bob was skipped
      assert TurnLogic.skipped_players(@players, @n, 0, 2) == [%{name: "bob"}]
    end

    test "returns multiple skipped players" do
      # alice(0) -> dave(3): bob and carol were skipped
      assert TurnLogic.skipped_players(@players, @n, 0, 3) == [%{name: "bob"}, %{name: "carol"}]
    end

    test "returns skipped player on wrap-around" do
      # dave(3) -> bob(1): alice was skipped after wrap
      assert TurnLogic.skipped_players(@players, @n, 3, 1) == [%{name: "alice"}]
    end

    test "returns skipped player wrapping from middle" do
      # carol(2) -> alice(0): dave was skipped
      assert TurnLogic.skipped_players(@players, @n, 2, 0) == [%{name: "dave"}]
    end
  end
end
