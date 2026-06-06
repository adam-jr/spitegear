defmodule Spitegear.LiveGameState.RoundData do
  @moduledoc """
  Derived round structure for a game, built from a chronological turn list in
  a single O(n) pass.

  Round boundaries are inferred from the observed turn order alone — no
  elimination data is required. A new round begins the first time a player
  appears a second time within the current round.

  The caller must supply the `WargearViewScreenDb` for the game. It is stored
  on the struct for downstream use (e.g. knowing the full player roster) and
  will eventually participate in round-detection logic. Pass `nil` when no
  view screen is available.

  ## Derived helpers

  - `new_round_started?/1` — true when the current (last) round has exactly one turn.
  """

  alias Spitegear.LiveGameState.Round
  alias Spitegear.LiveGameState.Turn
  alias Spitegear.LiveGameState.WargearViewScreenDb

  @type t :: %__MODULE__{
          rounds: [Round.t()],
          current_round: pos_integer() | nil,
          completed_rounds: non_neg_integer(),
          view_screen: WargearViewScreenDb.t() | nil
        }

  defstruct rounds: [], current_round: nil, completed_rounds: 0, view_screen: nil

  @doc """
  Builds a `RoundData` from a chronological list of turns and the game's
  `WargearViewScreenDb`. Pass `nil` for `view_screen` when unavailable.

  Returns an empty struct (with `view_screen` set) when `turns` is empty.
  """
  @spec build_round_data([Turn.t()], WargearViewScreenDb.t() | nil) :: t()
  def build_round_data([], view_screen), do: %__MODULE__{view_screen: view_screen}

  def build_round_data(turns, view_screen) do
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

    %__MODULE__{
      rounds: Enum.reverse([last_round | completed]),
      current_round: round_number,
      completed_rounds: round_number - 1,
      view_screen: view_screen
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
