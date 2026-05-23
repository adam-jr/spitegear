defmodule Spitegear.GameLog.ParserTest do
  use ExUnit.Case, async: true

  alias Spitegear.GameLog.Parser

  # Helper: build a minimal row map with only :action set
  defp row(action, extra \\ %{}) do
    Map.merge(%{action: action, ad: nil, dd: nil, bmod: nil, al: nil, dl: nil}, extra)
  end

  describe "parse_row/1 — setup and turn lifecycle" do
    test "setup" do
      assert {:ok, %{event_type: "setup"}} = Parser.parse_row(row("Initial board setup complete"))
    end

    test "started_turn" do
      assert {:ok, %{event_type: "started_turn", attacker: "adam jormp jomp"}} =
               Parser.parse_row(row("adam jormp jomp started turn"))
    end

    test "ended_turn" do
      assert {:ok, %{event_type: "ended_turn", attacker: "Player One"}} =
               Parser.parse_row(row("Player One ended turn"))
    end
  end

  describe "parse_row/1 — unit placement" do
    test "received_units" do
      assert {:ok, %{event_type: "received_units", attacker: "dandodd", units: 5}} =
               Parser.parse_row(row("dandodd received 5 units"))
    end

    test "received_units singular" do
      assert {:ok, %{event_type: "received_units", attacker: "Player", units: 1}} =
               Parser.parse_row(row("Player received 1 unit"))
    end

    test "received_bonus" do
      assert {:ok, %{event_type: "received_bonus", attacker: "dandodd", units: 3}} =
               Parser.parse_row(row("dandodd received 3 bonus units"))
    end

    test "placed_units" do
      assert {:ok, %{event_type: "placed_units", attacker: "dandodd", units: 2, territory_to: "North Africa"}} =
               Parser.parse_row(row("dandodd placed 2 units on North Africa"))
    end

    test "placed_units singular" do
      assert {:ok, %{event_type: "placed_units", attacker: "Player", units: 1, territory_to: "Alaska"}} =
               Parser.parse_row(row("Player placed 1 unit on Alaska"))
    end
  end

  describe "parse_row/1 — combat" do
    test "attacked with dice columns" do
      result =
        Parser.parse_row(
          row(
            "dandodd attacked pants off vant hof The Disputed Lands > The Flatlands (5,3,3) (2,2)",
            %{ad: "5,3,3", dd: "2,2", bmod: "0", al: "0", dl: "1"}
          )
        )

      assert {:ok,
              %{
                event_type: "attacked",
                attacker: "dandodd",
                territory_to: "The Flatlands",
                attacker_dice: "5,3,3",
                defender_dice: "2,2",
                battle_mod: "0",
                attacker_losses: 0,
                defender_losses: 1
              }} = result
    end

    test "attacked with battle modifier in action string" do
      result =
        Parser.parse_row(
          row("dandodd attacked foo > Brazil (4,2,1)-1 (4,2)", %{ad: "4,2,1", dd: "4,2", bmod: "-1,0", al: "1", dl: "0"})
        )

      assert {:ok, %{event_type: "attacked", territory_to: "Brazil", attacker_losses: 1, defender_losses: 0}} =
               result
    end

    test "occupied" do
      assert {:ok, %{event_type: "occupied", attacker: "dandodd", territory_to: "The Flatlands", units: 3}} =
               Parser.parse_row(row("dandodd occupied foo > The Flatlands with 3 units"))
    end

    test "occupied singular unit" do
      assert {:ok, %{event_type: "occupied", units: 1}} =
               Parser.parse_row(row("P occupied foo > Bar with 1 unit"))
    end

    test "attacked with pre-modifier (+N before attacker dice) and post-modifier (+N after defender dice)" do
      result =
        Parser.parse_row(
          row(
            "Hesh attacked ZachClash Union Fleet 4 > Charleston +0 (5,1) (1)+1",
            %{ad: "5,1", dd: "1", bmod: "0,1", al: "0", dl: "1"}
          )
        )

      assert {:ok,
              %{
                event_type: "attacked",
                attacker: "Hesh",
                territory_to: "Charleston",
                attacker_losses: 0,
                defender_losses: 1
              }} = result
    end

    test "attacked pre+post modifier with multi-word territory" do
      assert {:ok, %{event_type: "attacked", attacker: "Hesh", territory_to: "Olustee"}} =
               Parser.parse_row(
                 row("Hesh attacked Tallness Union Fleet 5 > Olustee +0 (5,5) (7)+1")
               )
    end
  end

  describe "parse_row/1 — movement" do
    test "fortified" do
      assert {:ok,
              %{
                event_type: "fortified",
                attacker: "dandodd",
                units: 5,
                territory_from: "Ukraine",
                territory_to: "Afghanistan"
              }} =
               Parser.parse_row(row("dandodd fortified 5 units Ukraine > Afghanistan"))
    end

    test "transferred" do
      assert {:ok,
              %{
                event_type: "transferred",
                attacker: "Player",
                units: 2,
                territory_from: "Egypt",
                territory_to: "East Africa"
              }} =
               Parser.parse_row(row("Player transferred 2 units Egypt > East Africa"))
    end
  end

  describe "parse_row/1 — cards" do
    test "awarded_card" do
      assert {:ok, %{event_type: "awarded_card", attacker: "dandodd"}} =
               Parser.parse_row(row("dandodd awarded card"))
    end

    test "traded_cards" do
      assert {:ok, %{event_type: "traded_cards", attacker: "dandodd"}} =
               Parser.parse_row(row("dandodd traded cards (ABC) for 4 units"))
    end

    test "traded_card singular" do
      assert {:ok, %{event_type: "traded_cards", attacker: "Player"}} =
               Parser.parse_row(row("Player traded card"))
    end
  end

  describe "parse_row/1 — game end events" do
    test "eliminated" do
      assert {:ok, %{event_type: "eliminated", attacker: "dandodd", defender: "pants off vant hof"}} =
               Parser.parse_row(row("dandodd eliminated pants off vant hof"))
    end

    test "game_won by prefix" do
      assert {:ok, %{event_type: "game_won", attacker: "dandodd"}} =
               Parser.parse_row(row("Game won by dandodd"))
    end

    test "game_won suffix" do
      assert {:ok, %{event_type: "game_won", attacker: "dandodd"}} =
               Parser.parse_row(row("dandodd won"))
    end

    test "surrendered" do
      assert {:ok, %{event_type: "surrendered", attacker: "Player One"}} =
               Parser.parse_row(row("Player One surrendered"))
    end

    test "timed_out" do
      assert {:ok, %{event_type: "timed_out", attacker: "Lazy Player"}} =
               Parser.parse_row(row("Lazy Player timed out"))
    end
  end

  describe "parse_row/1 — unrecognized" do
    test "returns unrecognized for unknown action" do
      assert {:unrecognized, "some unknown action string"} =
               Parser.parse_row(row("some unknown action string"))
    end

    test "does not match partial started_turn" do
      assert {:unrecognized, _} = Parser.parse_row(row("player started their turn today"))
    end
  end
end
