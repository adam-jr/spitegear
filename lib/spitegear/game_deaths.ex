defmodule Spitegear.GameDeaths do
  @moduledoc """
  Context for reading and writing `GameDeath` records.
  """

  import Ecto.Query

  alias Spitegear.GameDeath
  alias Spitegear.Repo

  @type game_id :: String.t()

  @doc """
  Records a player elimination for `game_id`. Pass `inferred: true` when the
  death was inferred from a skipped turn rather than read directly from the
  view screen. Safe to call more than once — duplicate inserts (same game and
  player) are silently ignored.
  """
  @spec create(game_id(), String.t(), DateTime.t(), inferred: boolean()) ::
          {:ok, GameDeath.t()} | {:error, Ecto.Changeset.t()}
  def create(game_id, player_name, eliminated_at, opts \\ []) do
    Repo.insert(
      %GameDeath{
        game_id: game_id,
        player_name: player_name,
        eliminated_at: eliminated_at,
        inferred: Keyword.get(opts, :inferred, false)
      },
      on_conflict: :nothing,
      conflict_target: [:game_id, :player_name]
    )
  end

  @doc "Returns all recorded player deaths for `game_id`."
  @spec list(game_id()) :: [GameDeath.t()]
  def list(game_id) do
    Repo.all(from(d in GameDeath, where: d.game_id == ^game_id))
  end
end
