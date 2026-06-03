defmodule Spitegear.Turns do
  @moduledoc """
  Context for querying turn history data.
  """
  import Ecto.Query

  alias Spitegear.Repo
  alias Spitegear.TurnHistory
  alias Spitegear.TurnHistory.Round

  @doc """
  Returns all turns for `game_id` grouped into rounds, in chronological order.

  A round boundary is detected when a player reappears. The last round always
  has `complete: false` because completion of the in-progress round can only
  be determined by knowing the current live player — see
  `LiveGameState.completed_rounds/2`.
  """
  @spec list_rounds(String.t()) :: [Round.t()]
  def list_rounds(game_id) do
    Repo.all(
      from(t in TurnHistory,
        where: t.game_id == ^game_id,
        order_by: [asc: t.started]
      )
    )
    |> to_rounds()
  end

  defp to_rounds([]), do: []

  defp to_rounds(turns) do
    {complete_rounds, current_round} =
      Enum.reduce(turns, {[], []}, fn turn, {rounds, current} ->
        if turn.player_name in Enum.map(current, & &1.player_name) do
          complete = %Round{turns: Enum.reverse(current), complete: true}
          {[complete | rounds], [turn]}
        else
          {rounds, [turn | current]}
        end
      end)

    last = %Round{turns: Enum.reverse(current_round), complete: false}
    Enum.reverse([last | complete_rounds])
  end
end
