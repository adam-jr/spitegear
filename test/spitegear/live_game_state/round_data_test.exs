defmodule Spitegear.LiveGameState.RoundDataTest do
  use ExUnit.Case, async: true

  alias Spitegear.LiveGameState.Round
  alias Spitegear.LiveGameState.RoundData
  alias Spitegear.LiveGameState.Turn

  defp turn(name), do: %Turn{player_name: name}
  defp turns(names), do: Enum.map(names, &turn/1)

  describe "build_round_data/1" do
    test "returns empty struct for empty list" do
      assert %RoundData{rounds: [], current_round: nil, completed_rounds: 0} ==
               RoundData.build_round_data([])
    end

    test "single turn produces one round" do
      result = RoundData.build_round_data(turns(~w[A]))

      assert result.current_round == 1
      assert result.completed_rounds == 0
      assert [%Round{round_number: 1, turns: [%Turn{player_name: "A"}]}] = result.rounds
    end

    test "A B C — one round, no repeat" do
      result = RoundData.build_round_data(turns(~w[A B C]))

      assert result.current_round == 1
      assert result.completed_rounds == 0
      assert length(result.rounds) == 1
      assert player_names(result.rounds, 1) == ~w[A B C]
    end

    test "A B C A — round boundary on second A" do
      result = RoundData.build_round_data(turns(~w[A B C A]))

      assert result.current_round == 2
      assert result.completed_rounds == 1
      assert length(result.rounds) == 2
      assert player_names(result.rounds, 1) == ~w[A B C]
      assert player_names(result.rounds, 2) == ~w[A]
    end

    test "A B C A B — two rounds, second partially complete" do
      result = RoundData.build_round_data(turns(~w[A B C A B]))

      assert result.current_round == 2
      assert result.completed_rounds == 1
      assert player_names(result.rounds, 1) == ~w[A B C]
      assert player_names(result.rounds, 2) == ~w[A B]
    end

    test "A B C A B C A — three rounds" do
      result = RoundData.build_round_data(turns(~w[A B C A B C A]))

      assert result.current_round == 3
      assert result.completed_rounds == 2
      assert length(result.rounds) == 3
      assert player_names(result.rounds, 1) == ~w[A B C]
      assert player_names(result.rounds, 2) == ~w[A B C]
      assert player_names(result.rounds, 3) == ~w[A]
    end

    test "A B C A B A — elimination-style, no explicit elimination data needed" do
      result = RoundData.build_round_data(turns(~w[A B C A B A]))

      assert result.current_round == 3
      assert result.completed_rounds == 2
      assert player_names(result.rounds, 1) == ~w[A B C]
      assert player_names(result.rounds, 2) == ~w[A B]
      assert player_names(result.rounds, 3) == ~w[A]
    end

    test "turns list preserves order within each round" do
      result = RoundData.build_round_data(turns(~w[A B C D A]))

      assert player_names(result.rounds, 1) == ~w[A B C D]
      assert player_names(result.rounds, 2) == ~w[A]
    end

    test "round_number on each Round struct matches position" do
      result = RoundData.build_round_data(turns(~w[A B A B A]))

      assert Enum.map(result.rounds, & &1.round_number) == [1, 2, 3]
    end
  end

  describe "new_round_started?/1" do
    test "false for empty RoundData" do
      refute RoundData.new_round_started?(%RoundData{})
    end

    test "true when current round has exactly one turn" do
      result = RoundData.build_round_data(turns(~w[A B C A]))
      assert RoundData.new_round_started?(result)
    end

    test "false when current round has more than one turn" do
      result = RoundData.build_round_data(turns(~w[A B C A B]))
      refute RoundData.new_round_started?(result)
    end

    test "true for the very first turn of the game" do
      result = RoundData.build_round_data(turns(~w[A]))
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
