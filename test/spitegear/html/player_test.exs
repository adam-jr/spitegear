defmodule Spitegear.HTML.PlayerTest do
  use ExUnit.Case, async: true

  alias Spitegear.HTML.Player

  @fixture Path.expand("../../support/fixtures/player_rows.html", __DIR__)

  setup_all do
    {:ok, doc} = @fixture |> File.read!() |> Floki.parse_document()

    rows =
      doc
      |> Floki.find("div#playerstats tr")
      |> Enum.drop(1)

    players =
      rows
      |> Enum.with_index(1)
      |> Enum.map(fn {row, seat} ->
        %{Player.from_table_row(row) | seat_number: seat}
      end)

    %{hesh: Enum.at(players, 0), kyjygyfyf: Enum.at(players, 1), adam: Enum.at(players, 2)}
  end

  describe "card_count/1" do
    test "parses a normal card count", %{hesh: player} do
      assert player.card_count == 5
    end

    test "returns 0 for an eliminated player with empty cards cell", %{kyjygyfyf: player} do
      assert player.card_count == 0
    end

    test "strips the (B) bonus suffix and returns the count", %{adam: player} do
      assert player.card_count == 1
    end
  end

  describe "from_table_row/1" do
    test "parses player name", %{hesh: player} do
      assert player.name == "Hesh"
    end

    test "parses player color from inline style", %{hesh: player} do
      assert player.color == "#ffff00"
    end

    test "detects current turn from active clock span", %{adam: player} do
      assert player.current_turn? == true
    end

    test "returns false for current_turn? when clock span is empty", %{hesh: player} do
      assert player.current_turn? == false
    end

    test "detects eliminated status", %{kyjygyfyf: player} do
      assert player.eliminated? == true
    end

    test "returns false for eliminated? when player is active", %{hesh: player} do
      assert player.eliminated? == false
    end
  end
end
