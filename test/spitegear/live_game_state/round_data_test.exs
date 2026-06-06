defmodule Spitegear.LiveGameState.RoundDataTest do
  use ExUnit.Case, async: true

  alias Spitegear.LiveGameState.Round
  alias Spitegear.LiveGameState.RoundData
  alias Spitegear.LiveGameState.Turn
  alias Spitegear.LiveGameState.WargearViewScreenDb

  @game_id "round_data_test_game"
  @base ~U[2024-01-01 00:00:00Z]

  # Builds in-memory Turn structs with sequential hourly timestamps.
  # The final turn has ended_at: nil, representing the in-progress turn.
  defp turns(names) do
    total = length(names)

    names
    |> Enum.with_index()
    |> Enum.map(fn {name, i} ->
      %Turn{
        game_id: @game_id,
        player_name: name,
        started_at: DateTime.add(@base, i * 3600, :second),
        ended_at: if(i == total - 1, do: nil, else: DateTime.add(@base, (i + 1) * 3600, :second))
      }
    end)
  end

  defp view_screen(player_names) do
    %WargearViewScreenDb{
      game_id: @game_id,
      players: Enum.map(player_names, &%{"name" => &1, "slack_name" => "@#{&1}"}),
      eliminated: [],
      winners: [],
      fogged: false
    }
  end

  describe "build_round_data/2" do
    test "returns empty struct for empty turns list" do
      vs = view_screen(~w[A B C])
      result = RoundData.build_round_data([], vs)

      assert result.rounds == []
      assert result.current_round == nil
      assert result.completed_rounds == 0
      assert result.view_screen == vs
    end

    test "stores view_screen on the struct" do
      vs = view_screen(~w[A B C])
      result = RoundData.build_round_data(turns(~w[A]), vs)

      assert result.view_screen == vs
    end

    test "accepts nil view_screen" do
      result = RoundData.build_round_data(turns(~w[A B C]), nil)

      assert result.current_round == 1
      assert result.view_screen == nil
    end

    test "single in-progress turn produces one round" do
      result = RoundData.build_round_data(turns(~w[A]), view_screen(~w[A B C]))

      assert result.current_round == 1
      assert result.completed_rounds == 0
      assert [%Round{round_number: 1}] = result.rounds
      assert player_names(result.rounds, 1) == ~w[A]
    end

    test "A B C — one round, no repeat, C is in progress" do
      result = RoundData.build_round_data(turns(~w[A B C]), view_screen(~w[A B C]))

      assert result.current_round == 1
      assert result.completed_rounds == 0
      assert player_names(result.rounds, 1) == ~w[A B C]
    end

    test "A B C A — round boundary on second A, A is in progress" do
      result = RoundData.build_round_data(turns(~w[A B C A]), view_screen(~w[A B C]))

      assert result.current_round == 2
      assert result.completed_rounds == 1
      assert length(result.rounds) == 2
      assert player_names(result.rounds, 1) == ~w[A B C]
      assert player_names(result.rounds, 2) == ~w[A]
    end

    test "A B C A B — two rounds, B is in progress" do
      result = RoundData.build_round_data(turns(~w[A B C A B]), view_screen(~w[A B C]))

      assert result.current_round == 2
      assert result.completed_rounds == 1
      assert player_names(result.rounds, 1) == ~w[A B C]
      assert player_names(result.rounds, 2) == ~w[A B]
    end

    test "A B C A B C A — three rounds, A is in progress" do
      result = RoundData.build_round_data(turns(~w[A B C A B C A]), view_screen(~w[A B C]))

      assert result.current_round == 3
      assert result.completed_rounds == 2
      assert length(result.rounds) == 3
      assert player_names(result.rounds, 1) == ~w[A B C]
      assert player_names(result.rounds, 2) == ~w[A B C]
      assert player_names(result.rounds, 3) == ~w[A]
    end

    test "A B C A B A — elimination-style, no elimination data needed, A is in progress" do
      result = RoundData.build_round_data(turns(~w[A B C A B A]), view_screen(~w[A B C]))

      assert result.current_round == 3
      assert result.completed_rounds == 2
      assert player_names(result.rounds, 1) == ~w[A B C]
      assert player_names(result.rounds, 2) == ~w[A B]
      assert player_names(result.rounds, 3) == ~w[A]
    end

    test "round_number on each Round struct matches position" do
      result = RoundData.build_round_data(turns(~w[A B A B A]), view_screen(~w[A B]))

      assert Enum.map(result.rounds, & &1.round_number) == [1, 2, 3]
    end

    test "final in-progress turn has nil ended_at" do
      ts = turns(~w[A B C A])
      assert List.last(ts).ended_at == nil
      assert List.last(ts).player_name == "A"

      result = RoundData.build_round_data(ts, view_screen(~w[A B C]))
      [_r1, r2] = result.rounds
      assert List.last(r2.turns).ended_at == nil
    end
  end

  describe "new_round_started?/1" do
    test "false for empty RoundData" do
      refute RoundData.new_round_started?(%RoundData{})
    end

    test "true when current round has exactly one turn (A is in progress after completing round 1)" do
      result = RoundData.build_round_data(turns(~w[A B C A]), view_screen(~w[A B C]))
      assert RoundData.new_round_started?(result)
    end

    test "false when current round has more than one turn" do
      result = RoundData.build_round_data(turns(~w[A B C A B]), view_screen(~w[A B C]))
      refute RoundData.new_round_started?(result)
    end

    test "true for the very first turn of the game" do
      result = RoundData.build_round_data(turns(~w[A]), view_screen(~w[A B C]))
      assert RoundData.new_round_started?(result)
    end
  end

  # --- Helpers ---

  defp player_names(rounds, round_number) do
    rounds
    |> Enum.find(&(&1.round_number == round_number))
    |> Map.fetch!(:turns)
    |> Enum.map(& &1.player_name)
  end
end
