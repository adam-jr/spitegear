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
      assert {:ok, %{event_type: "started_turn", player: "adam jormp jomp"}} =
               Parser.parse_row(row("adam jormp jomp started turn"))
    end

    test "ended_turn" do
      assert {:ok, %{event_type: "ended_turn", player: "Player One"}} =
               Parser.parse_row(row("Player One ended turn"))
    end
  end

  describe "parse_row/1 — unit placement" do
    test "received_units" do
      assert {:ok, %{event_type: "received_units", player: "dandodd", units: 5}} =
               Parser.parse_row(row("dandodd received 5 units"))
    end

    test "received_units singular" do
      assert {:ok, %{event_type: "received_units", player: "Player", units: 1}} =
               Parser.parse_row(row("Player received 1 unit"))
    end

    test "received_bonus" do
      assert {:ok, %{event_type: "received_bonus", player: "dandodd", units: 3}} =
               Parser.parse_row(row("dandodd received 3 bonus units"))
    end

    test "placed_units" do
      assert {:ok,
              %{
                event_type: "placed_units",
                player: "dandodd",
                units: 2,
                territory_to: "North Africa"
              }} =
               Parser.parse_row(row("dandodd placed 2 units on North Africa"))
    end

    test "placed_units singular" do
      assert {:ok,
              %{event_type: "placed_units", player: "Player", units: 1, territory_to: "Alaska"}} =
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
                player: "dandodd",
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
          row("dandodd attacked foo > Brazil (4,2,1)-1 (4,2)", %{
            ad: "4,2,1",
            dd: "4,2",
            bmod: "-1,0",
            al: "1",
            dl: "0"
          })
        )

      assert {:ok,
              %{
                event_type: "attacked",
                territory_to: "Brazil",
                attacker_losses: 1,
                defender_losses: 0
              }} =
               result
    end

    test "occupied" do
      assert {:ok,
              %{
                event_type: "occupied",
                player: "dandodd",
                territory_to: "The Flatlands",
                units: 3
              }} =
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
                player: "Hesh",
                territory_to: "Charleston",
                attacker_losses: 0,
                defender_losses: 1
              }} = result
    end

    test "attacked pre+post modifier with multi-word territory" do
      assert {:ok, %{event_type: "attacked", player: "Hesh", territory_to: "Olustee"}} =
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
                player: "dandodd",
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
                player: "Player",
                units: 2,
                territory_from: "Egypt",
                territory_to: "East Africa"
              }} =
               Parser.parse_row(row("Player transferred 2 units Egypt > East Africa"))
    end
  end

  describe "parse_row/1 — factory produced" do
    test "factory_produced with trailing modifier" do
      assert {:ok,
              %{
                event_type: "factory_produced",
                player: "pants off vant hof",
                units: 4,
                territory_to: "The Eyrie"
              }} =
               Parser.parse_row(
                 row("pants off vant hof factory produced 4 units on The Eyrie +1")
               )
    end

    test "factory_produced without trailing modifier" do
      assert {:ok,
              %{
                event_type: "factory_produced",
                player: "Player",
                units: 3,
                territory_to: "Alaska"
              }} =
               Parser.parse_row(row("Player factory produced 3 units on Alaska"))
    end

    test "factory_produced singular unit" do
      assert {:ok, %{event_type: "factory_produced", units: 1}} =
               Parser.parse_row(row("Player factory produced 1 unit on Alaska"))
    end
  end

  describe "parse_row/1 — cards" do
    test "awarded_card" do
      assert {:ok, %{event_type: "awarded_card", player: "dandodd"}} =
               Parser.parse_row(row("dandodd awarded card"))
    end

    test "traded_cards with unit count" do
      assert {:ok, %{event_type: "traded_cards", player: "dandodd", units: 4}} =
               Parser.parse_row(row("dandodd traded cards (ABC) for 4 units"))
    end

    test "traded_cards with plural unit count" do
      assert {:ok, %{event_type: "traded_cards", player: "Player", units: 10}} =
               Parser.parse_row(row("Player traded cards (XYZ) for 10 units"))
    end

    test "traded_card singular without unit count" do
      assert {:ok, %{event_type: "traded_cards", player: "Player"}} =
               Parser.parse_row(row("Player traded card"))
    end
  end

  describe "parse_row/1 — elimination follow-on events" do
    test "received_elimination_bonus" do
      assert {:ok, %{event_type: "received_elimination_bonus", player: "dandodd", units: 10}} =
               Parser.parse_row(row("dandodd received elimination bonus of 10 units"))
    end

    test "received_elimination_bonus larger bonus" do
      assert {:ok, %{event_type: "received_elimination_bonus", player: "Kyjygyfyf", units: 12}} =
               Parser.parse_row(row("Kyjygyfyf received elimination bonus of 12 units"))
    end

    test "captured_cards" do
      assert {:ok,
              %{
                event_type: "captured_cards",
                player: "dandodd",
                units: 2,
                defender: "Tallness"
              }} =
               Parser.parse_row(row("dandodd captured 2 cards from Tallness"))
    end

    test "captured_cards with multi-word defender" do
      assert {:ok,
              %{
                event_type: "captured_cards",
                player: "dandodd",
                units: 3,
                defender: "pants off vant hof"
              }} =
               Parser.parse_row(row("dandodd captured 3 cards from pants off vant hof"))
    end

    test "captured_cards singular" do
      assert {:ok, %{event_type: "captured_cards", units: 1}} =
               Parser.parse_row(row("Player captured 1 card from Someone"))
    end
  end

  describe "parse_row/1 — factory destroyed" do
    test "factory_destroyed" do
      assert {:ok,
              %{
                event_type: "factory_destroyed",
                player: "Hesh",
                units: 2,
                territory_to: "The Redwyne Straits"
              }} =
               Parser.parse_row(row("Hesh factory destroyed 2 units on The Redwyne Straits"))
    end

    test "factory_destroyed singular unit" do
      assert {:ok,
              %{
                event_type: "factory_destroyed",
                player: "dandodd",
                units: 1,
                territory_to: "Bay of Seals"
              }} =
               Parser.parse_row(row("dandodd factory destroyed 1 unit on Bay of Seals"))
    end
  end

  describe "parse_row/1 — capital / neutralised / assimilated" do
    test "captured_capital" do
      assert {:ok,
              %{
                event_type: "captured_capital",
                player: "Hesh",
                territory_to: "Capital D Capital"
              }} =
               Parser.parse_row(row("Hesh captured Capital D Capital"))
    end

    test "neutralised (system event — no attacker)" do
      assert {:ok, %{event_type: "neutralised", territory_to: "D1", units: 1}} =
               Parser.parse_row(row("Neutralised D1 with 1 unit"))
    end

    test "neutralised with multi-word territory" do
      assert {:ok, %{event_type: "neutralised", territory_to: "D Command Center", units: 1}} =
               Parser.parse_row(row("Neutralised D Command Center with 1 unit"))
    end

    test "neutralised plural units" do
      assert {:ok, %{event_type: "neutralised", territory_to: "C7", units: 3}} =
               Parser.parse_row(row("Neutralised C7 with 3 units"))
    end

    test "assimilated" do
      assert {:ok, %{event_type: "assimilated", player: "Hesh", units: 3, territory_from: "C4"}} =
               Parser.parse_row(row("Hesh assimilated 3 units from C4"))
    end

    test "assimilated singular" do
      assert {:ok,
              %{
                event_type: "assimilated",
                player: "Hesh",
                units: 1,
                territory_from: "D Factory"
              }} =
               Parser.parse_row(row("Hesh assimilated 1 unit from D Factory"))
    end
  end

  describe "parse_row/1 — captured_reserve_units" do
    test "captured_reserve_units" do
      assert {:ok,
              %{
                event_type: "captured_reserve_units",
                player: "dandodd",
                units: 3,
                defender: "Kyjygyfyf"
              }} =
               Parser.parse_row(row("dandodd captured 3 reserve units from Kyjygyfyf"))
    end

    test "captured_reserve_units singular" do
      assert {:ok, %{event_type: "captured_reserve_units", units: 1}} =
               Parser.parse_row(row("Player captured 1 reserve unit from Other"))
    end
  end

  describe "parse_row/1 — game end events" do
    test "eliminated" do
      assert {:ok, %{event_type: "eliminated", player: "dandodd", defender: "pants off vant hof"}} =
               Parser.parse_row(row("dandodd eliminated pants off vant hof"))
    end

    test "game_won by prefix" do
      assert {:ok, %{event_type: "game_won", player: "dandodd"}} =
               Parser.parse_row(row("Game won by dandodd"))
    end

    test "game_won suffix" do
      assert {:ok, %{event_type: "game_won", player: "dandodd"}} =
               Parser.parse_row(row("dandodd won"))
    end

    test "surrendered" do
      assert {:ok, %{event_type: "surrendered", player: "Player One"}} =
               Parser.parse_row(row("Player One surrendered"))
    end

    test "timed_out" do
      assert {:ok, %{event_type: "timed_out", player: "Lazy Player"}} =
               Parser.parse_row(row("Lazy Player timed out"))
    end
  end

  describe "parse_row/1 — setup events" do
    test "game_started" do
      assert {:ok, %{event_type: "game_started"}} = Parser.parse_row(row("Game started"))
    end

    test "fogged" do
      assert {:ok, %{event_type: "fogged"}} = Parser.parse_row(row("Fogged"))
    end
  end

  describe "parse_row/1 — game setup (factory/seat/territory drafting)" do
    test "assigned_factory" do
      assert {:ok,
              %{
                event_type: "assigned_factory",
                territory_to: "Nothgierc",
                player: "pants off vant hof"
              }} =
               Parser.parse_row(row("Assigned factory Nothgierc to pants off vant hof"))
    end

    test "assigned_factory with multi-word territory" do
      assert {:ok, %{event_type: "assigned_factory", territory_to: "The Eyrie", player: "Hesh"}} =
               Parser.parse_row(row("Assigned factory The Eyrie to Hesh"))
    end

    test "assigned_seat" do
      assert {:ok, %{event_type: "assigned_seat", seat: 1, player: "Kyjygyfyf"}} =
               Parser.parse_row(row("Assigned seat 1 to Kyjygyfyf"))
    end

    test "assigned_seat multi-word player" do
      assert {:ok, %{event_type: "assigned_seat", seat: 3, player: "pants off vant hof"}} =
               Parser.parse_row(row("Assigned seat 3 to pants off vant hof"))
    end

    test "selected_territory" do
      assert {:ok,
              %{event_type: "selected_territory", player: "Hesh", territory_to: "Brindlewood"}} =
               Parser.parse_row(row("Hesh selected Brindlewood"))
    end

    test "selected_territory multi-word" do
      assert {:ok,
              %{
                event_type: "selected_territory",
                player: "dandodd",
                territory_to: "North Africa"
              }} =
               Parser.parse_row(row("dandodd selected North Africa"))
    end

    test "selected_territory empty pick" do
      assert {:ok, %{event_type: "selected_territory", player: "Hesh"}} =
               Parser.parse_row(row("Hesh selected"))
    end
  end

  describe "parse_row/1 — skipped_turn" do
    test "skipped_turn" do
      assert {:ok, %{event_type: "skipped_turn", player: "Player One"}} =
               Parser.parse_row(row("Player One skipped turn"))
    end
  end

  describe "parse_row/1 — bonus unit singular" do
    test "received_bonus singular" do
      assert {:ok, %{event_type: "received_bonus", player: "Hesh", units: 1}} =
               Parser.parse_row(row("Hesh received 1 bonus unit"))
    end
  end

  describe "parse_row/1 — placed units with empty territory" do
    test "placed_units with no territory" do
      assert {:ok, %{event_type: "placed_units", player: "Player", units: 2, territory_to: nil}} =
               Parser.parse_row(row("Player placed 2 units on"))
    end
  end

  describe "parse_row/1 — attacked with units/percentage format" do
    test "attacked with unit count and percentages (no dice columns)" do
      result =
        Parser.parse_row(
          row("Hesh attacked Kyjygyfyf Crumb > Easter Bunny with 8 units (65% vs 70%) AL1 / DL1")
        )

      assert {:ok,
              %{
                event_type: "attacked",
                player: "Hesh",
                territory_to: "Easter Bunny",
                units: 8,
                attacker_losses: 1,
                defender_losses: 1
              }} = result
    end

    test "attacked with unit count and percentages — zero losses" do
      result =
        Parser.parse_row(row("dandodd attacked foo > Brazil with 5 units (50% vs 60%) AL0 / DL2"))

      assert {:ok,
              %{
                event_type: "attacked",
                player: "dandodd",
                territory_to: "Brazil",
                units: 5,
                attacker_losses: 0,
                defender_losses: 2
              }} = result
    end
  end

  describe "parse_row/1 — reinforced" do
    test "reinforced" do
      assert {:ok,
              %{
                event_type: "reinforced",
                player: "Hesh",
                units: 10,
                territory_from: "Chef",
                territory_to: "Dragonfruit"
              }} =
               Parser.parse_row(row("Hesh reinforced 10 units Chef > Dragonfruit"))
    end

    test "reinforced singular unit" do
      assert {:ok, %{event_type: "reinforced", units: 1}} =
               Parser.parse_row(row("Player reinforced 1 unit A > B"))
    end
  end

  describe "parse_row/1 — fortified with no destination" do
    test "fortified with empty destination" do
      assert {:ok,
              %{
                event_type: "fortified",
                player: "Player",
                units: 3,
                territory_from: "Ukraine"
              }} =
               Parser.parse_row(row("Player fortified 3 units Ukraine >"))
    end
  end

  describe "parse_row/1 — discarded_units" do
    test "discarded_units" do
      assert {:ok, %{event_type: "discarded_units", player: "Hesh", units: 7}} =
               Parser.parse_row(row("Hesh discarded 7 units"))
    end

    test "discarded_units singular" do
      assert {:ok, %{event_type: "discarded_units", player: "Player", units: 1}} =
               Parser.parse_row(row("Player discarded 1 unit"))
    end
  end

  describe "parse_row/1 — turn_order_set" do
    test "turn_order_set" do
      assert {:ok, %{event_type: "turn_order_set"}} =
               Parser.parse_row(row("Turn order set to 5,6,3,4,7,2,1"))
    end

    test "turn_order_set different order" do
      assert {:ok, %{event_type: "turn_order_set"}} =
               Parser.parse_row(row("Turn order set to 2,6,5,1,3,4,7"))
    end
  end

  describe "parse_row/1 — conquered_capital" do
    test "conquered_capital" do
      assert {:ok,
              %{
                event_type: "conquered_capital",
                player: "Kyjygyfyf",
                territory_to: "Capital p1"
              }} =
               Parser.parse_row(row("Kyjygyfyf conquered Capital p1"))
    end

    test "conquered_capital multi-word player" do
      assert {:ok,
              %{
                event_type: "conquered_capital",
                player: "pants off vant hof",
                territory_to: "Capital p3"
              }} =
               Parser.parse_row(row("pants off vant hof conquered Capital p3"))
    end
  end

  describe "parse_row/1 — attacked with no territory_to" do
    # Floki produces double whitespace after ">" when the territory_to cell is empty in the HTML
    test "attacked no territory_to — double space after > (production format)" do
      result =
        Parser.parse_row(
          row(
            "pants off vant hof attacked Hesh Burkina Faso >  (5,5,3) (6,2)",
            %{ad: "5,5,3", dd: "6,2", bmod: "0", al: "0", dl: "1"}
          )
        )

      assert {:ok,
              %{
                event_type: "attacked",
                player: "pants off vant hof",
                territory_to: nil,
                attacker_dice: "5,5,3",
                defender_dice: "6,2",
                attacker_losses: 0,
                defender_losses: 1
              }} = result
    end

    test "attacked no territory_to — single dice each" do
      assert {:ok, %{event_type: "attacked", player: "Hesh", territory_to: nil}} =
               Parser.parse_row(row("Hesh attacked pants off vant hof Guinea >  (4,1) (3,2)"))
    end

    test "attacked no territory_to — game 784989 seq 702" do
      assert {:ok, %{event_type: "attacked", territory_to: nil}} =
               Parser.parse_row(row("Hesh attacked pants off vant hof Guinea >  (1) (4)"))
    end

    test "attacked no territory_to — game 784989 seq 1530" do
      assert {:ok, %{event_type: "attacked", player: "adam jormp jomp", territory_to: nil}} =
               Parser.parse_row(
                 row("adam jormp jomp attacked pants off vant hof Ghana >  (3,1) (1)")
               )
    end

    test "attacked no territory_to — game 784989 seq 1557" do
      assert {:ok, %{event_type: "attacked", territory_to: nil}} =
               Parser.parse_row(
                 row("pants off vant hof attacked adam jormp jomp Burkina Faso >  (6,3,2) (6,5)")
               )
    end

    test "attacked no territory_to — game 784989 seq 1609" do
      assert {:ok, %{event_type: "attacked", territory_to: nil}} =
               Parser.parse_row(
                 row("pants off vant hof attacked adam jormp jomp Guinea >  (6,2,1) (3)")
               )
    end
  end

  describe "parse_row/1 — occupied with no territory_to" do
    # Floki produces double whitespace after ">" when the territory_to cell is empty in the HTML
    test "occupied no territory_to — double space after > (production format)" do
      assert {:ok,
              %{
                event_type: "occupied",
                player: "pants off vant hof",
                territory_to: nil,
                units: 2
              }} =
               Parser.parse_row(
                 row("pants off vant hof occupied Hesh Burkina Faso >  with 2 units")
               )
    end

    test "occupied no territory_to — game 784989 seq 1531" do
      assert {:ok,
              %{event_type: "occupied", player: "adam jormp jomp", territory_to: nil, units: 2}} =
               Parser.parse_row(
                 row("adam jormp jomp occupied pants off vant hof Ghana >  with 2 units")
               )
    end

    test "occupied no territory_to — game 784989 seq 1610" do
      assert {:ok, %{event_type: "occupied", territory_to: nil, units: 3}} =
               Parser.parse_row(
                 row("pants off vant hof occupied adam jormp jomp Guinea >  with 3 units")
               )
    end

    test "occupied no territory_to — single space still works" do
      assert {:ok, %{event_type: "occupied", territory_to: nil, units: 1}} =
               Parser.parse_row(row("Player occupied Foo Bar > with 1 unit"))
    end
  end

  describe "parse_row/1 — transferred edge cases" do
    # Floki produces double whitespace before ">" when the source territory cell is empty in the HTML
    test "transferred only destination — double space before > (production format)" do
      assert {:ok,
              %{
                event_type: "transferred",
                player: "adam jormp jomp",
                units: 6,
                territory_to: "Guinea"
              }} =
               Parser.parse_row(row("adam jormp jomp transferred 6 units  > Guinea"))
    end

    test "transferred only destination — game 784989 seq 1614" do
      assert {:ok,
              %{
                event_type: "transferred",
                player: "pants off vant hof",
                units: 2,
                territory_to: "Ghana"
              }} =
               Parser.parse_row(row("pants off vant hof transferred 2 units  > Ghana"))
    end

    test "transferred only destination — single space still works" do
      assert {:ok, %{event_type: "transferred", territory_to: "North Africa"}} =
               Parser.parse_row(row("Player transferred 3 units > North Africa"))
    end

    test "transferred only source (no destination)" do
      assert {:ok,
              %{
                event_type: "transferred",
                player: "pants off vant hof",
                units: 3,
                territory_from: "Guinea"
              }} =
               Parser.parse_row(row("pants off vant hof transferred 3 units Guinea >"))
    end

    test "transferred only source multi-word territory" do
      assert {:ok, %{event_type: "transferred", territory_from: "North Africa"}} =
               Parser.parse_row(row("Player transferred 4 units North Africa >"))
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
