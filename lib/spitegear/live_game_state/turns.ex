defmodule Spitegear.LiveGameState.Turns do
  @moduledoc """
  Context for reading and writing `LiveGameState.Turn` records.
  """

  import Ecto.Query

  alias Spitegear.LiveGameState.Turn
  alias Spitegear.Repo

  @type game_id :: String.t()

  @doc "Returns all turns for `game_id`, ordered chronologically by `started_at`."
  @spec list_turns(game_id()) :: [Turn.t()]
  def list_turns(game_id) do
    Repo.all(
      from(t in Turn,
        where: t.game_id == ^game_id,
        order_by: [asc: t.started_at]
      )
    )
  end
end
