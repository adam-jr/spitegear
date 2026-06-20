defmodule Spitegear.Wargear.HTTP.ViewScreenTest do
  use ExUnit.Case, async: true

  alias Spitegear.Wargear.HTTP.ViewScreen

  @fixtures_dir Path.expand("../../../support/fixtures/view_screens", __DIR__)

  defp load_fixture(filename) do
    @fixtures_dir |> Path.join(filename) |> File.read!()
  end

  defp parse!(filename, game_id) do
    {:ok, vs} = filename |> load_fixture() |> ViewScreen.parse(game_id)
    vs
  end

  # ---------------------------------------------------------------------------
  # standard_no_fog_in_progress.html
  # Super Best Friends Bowl CXLVI — Civil War 1860, 7 players, no fog,
  # 4 eliminated, Hesh currently moving. adam jormp jomp has 2(BB) cards.
  # Captured 2026-06-20.
  # ---------------------------------------------------------------------------
  describe "standard_no_fog_in_progress" do
    setup do
      {:ok, vs: parse!("standard_no_fog_in_progress.html", "81533166")}
    end

    test "game metadata", %{vs: vs} do
      assert vs.game_id == "81533166"
      assert vs.game_name == "Super Best Friends Bowl CXLVI"
      assert vs.board_name == "Civil War 1860"
      assert vs.created == "Sat May 30, 2026 01:47"
      assert vs.finished == nil
      assert vs.fogged? == false
    end

    test "next card set worth", %{vs: vs} do
      assert vs.next_card == "60"
    end

    test "player count", %{vs: vs} do
      assert length(vs.players) == 7
    end

    test "current player", %{vs: vs} do
      assert vs.current_player.name == "Hesh"
    end

    test "eliminated players", %{vs: vs} do
      eliminated_names = vs.eliminated |> Enum.map(& &1.name) |> Enum.sort()

      assert eliminated_names ==
               ["ZachClash", "dandodd", "Kyjygyfyf", "pants off vant hof"] |> Enum.sort()
    end

    test "player card counts", %{vs: vs} do
      by_name = Map.new(vs.players, &{&1.name, &1.card_count})
      assert by_name["Hesh"] == 5
      assert by_name["Tallness"] == 4
      assert by_name["adam jormp jomp"] == 2
      assert by_name["Kyjygyfyf"] == 0
    end

    test "player colors", %{vs: vs} do
      by_name = Map.new(vs.players, &{&1.name, &1.color})
      assert by_name["Hesh"] == "#ffff00"
      assert by_name["adam jormp jomp"] == "#ffa500"
    end

    test "no winners yet", %{vs: vs} do
      assert vs.winners == []
    end
  end

  # ---------------------------------------------------------------------------
  # Add new fixtures below as they are collected. Name files to describe the
  # game variant: fogged_in_progress.html, finished_game.html,
  # cards_disabled.html, etc.
  # ---------------------------------------------------------------------------
end
