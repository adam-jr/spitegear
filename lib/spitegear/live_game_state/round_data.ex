defmodule Spitegear.LiveGameState.RoundData do
  @moduledoc """
  Derived round structure for a game, built from a chronological turn list in
  a single O(n) pass.

  Round boundaries are inferred from the observed turn order alone — no
  elimination data is required. A new round begins the first time a player
  appears a second time within the current round.

  ## Example

      iex> turns = [
      ...>   %Turn{player_name: "Alice"},
      ...>   %Turn{player_name: "Bob"},
      ...>   %Turn{player_name: "Charlie"},
      ...>   %Turn{player_name: "Alice"}
      ...> ]
      iex> RoundData.build_round_data(turns)
      %RoundData{
        current_round: 2,
        completed_rounds: 1,
        rounds: [
          %Round{round_number: 1, turns: [Alice, Bob, Charlie]},
          %Round{round_number: 2, turns: [Alice]}
        ]
      }

  ## Derived helpers

  - `new_round_started?/1` — true when the current (last) round has exactly one turn.
  """

  alias Spitegear.LiveGameState.Round
  alias Spitegear.LiveGameState.Turn

  @type t :: %__MODULE__{
          rounds: [Round.t()],
          current_round: pos_integer() | nil,
          completed_rounds: non_neg_integer()
        }

  defstruct rounds: [], current_round: nil, completed_rounds: 0

  @doc """
  Builds a `RoundData` from a chronological list of turns.

  Returns an empty struct when `turns` is empty.
  """
  @spec build_round_data([Turn.t()]) :: t()
  def build_round_data([]), do: %__MODULE__{}

  def build_round_data(turns) do
    initial = %{
      completed: [],
      current_turns: [],
      seen: MapSet.new(),
      round_number: 1
    }

    %{completed: completed, current_turns: current_turns, round_number: round_number} =
      Enum.reduce(turns, initial, fn turn, acc ->
        if MapSet.member?(acc.seen, turn.player_name) do
          finished = %Round{
            round_number: acc.round_number,
            turns: Enum.reverse(acc.current_turns)
          }

          %{
            acc
            | completed: [finished | acc.completed],
              current_turns: [turn],
              seen: MapSet.new([turn.player_name]),
              round_number: acc.round_number + 1
          }
        else
          %{
            acc
            | current_turns: [turn | acc.current_turns],
              seen: MapSet.put(acc.seen, turn.player_name)
          }
        end
      end)

    last_round = %Round{
      round_number: round_number,
      turns: Enum.reverse(current_turns)
    }

    all_rounds = Enum.reverse([last_round | completed])

    %__MODULE__{
      rounds: all_rounds,
      current_round: round_number,
      completed_rounds: round_number - 1
    }
  end

  @doc """
  Returns `true` when the current (last) round contains exactly one turn,
  indicating a new round just began.
  """
  @spec new_round_started?(t()) :: boolean()
  def new_round_started?(%__MODULE__{rounds: []}), do: false

  def new_round_started?(%__MODULE__{rounds: rounds}) do
    length(List.last(rounds).turns) == 1
  end
end
