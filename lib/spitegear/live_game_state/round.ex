defmodule Spitegear.LiveGameState.Round do
  @moduledoc """
  A single round within a game, containing the turns that occurred during it.
  """

  alias Spitegear.LiveGameState.Turn

  @type t :: %__MODULE__{
          round_number: pos_integer(),
          turns: [Turn.t()]
        }

  @enforce_keys [:round_number]
  defstruct [:round_number, turns: []]
end
