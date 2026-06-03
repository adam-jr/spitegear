defmodule Spitegear.LiveGameState.HistoryResponses do
  @moduledoc """
  Context for reading and writing `WargearHistoryApiResponseDb` records.
  """

  import Ecto.Query

  alias Spitegear.LiveGameState.WargearHistoryApiResponseDb
  alias Spitegear.Repo

  @type game_id :: String.t()

  @doc """
  Returns the most recent `WargearHistoryApiResponseDb` for `game_id`, or
  `nil` if none exists.
  """
  @spec get_latest(game_id()) :: WargearHistoryApiResponseDb.t() | nil
  def get_latest(game_id) do
    Repo.one(
      from(h in WargearHistoryApiResponseDb,
        where: h.game_id == ^game_id,
        order_by: [desc: h.inserted_at],
        limit: 1
      )
    )
  end

  @doc """
  Inserts a new record if the incoming `turn_data` has a different `turnid`
  than the most recently stored response for the game.

  Returns `{:ok, record}` on insert, `{:ok, :unchanged}` when the `turnid`
  has not changed, or `{:error, changeset}` on failure.
  """
  @spec record_if_changed(game_id(), map()) ::
          {:ok, WargearHistoryApiResponseDb.t()}
          | {:ok, :unchanged}
          | {:error, Ecto.Changeset.t()}
  def record_if_changed(game_id, turn_data) when is_map(turn_data) do
    case get_latest(game_id) do
      nil ->
        Repo.insert(%WargearHistoryApiResponseDb{game_id: game_id, turn_data: turn_data})

      existing ->
        if existing.turn_data["turnid"] != turn_data["turnid"] do
          Repo.insert(%WargearHistoryApiResponseDb{game_id: game_id, turn_data: turn_data})
        else
          {:ok, :unchanged}
        end
    end
  end

  @doc "Deletes records older than `days` days. Used by the pruning job."
  @spec prune(pos_integer()) :: {non_neg_integer(), nil}
  def prune(days \\ 90) do
    cutoff = DateTime.utc_now() |> DateTime.add(-days * 86_400)
    Repo.delete_all(from(h in WargearHistoryApiResponseDb, where: h.inserted_at < ^cutoff))
  end
end
