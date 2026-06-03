defmodule Spitegear.TurnHistory.Round do
  @moduledoc false

  alias Spitegear.TurnHistory

  @type t :: %__MODULE__{
          turns: [TurnHistory.t()],
          complete: boolean()
        }

  defstruct turns: [], complete: false
end
