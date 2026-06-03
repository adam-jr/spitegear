defmodule Spitegear.LiveGameState.ViewScreens do
  @moduledoc """
  Context for reading and writing `WargearViewScreenDb` snapshots.
  """

  import Ecto.Query

  alias Spitegear.LiveGameState.WargearViewScreenDb
  alias Spitegear.Repo
  alias Spitegear.Wargear.HTTP.ViewScreen, as: RawViewScreen

  @type game_id :: String.t()

  @doc """
  Returns the most recent `WargearViewScreenDb` snapshot for `game_id`, or
  `nil` if none exists.
  """
  @spec get_latest(game_id()) :: WargearViewScreenDb.t() | nil
  def get_latest(game_id) do
    Repo.one(
      from(v in WargearViewScreenDb,
        where: v.game_id == ^game_id,
        order_by: [desc: v.inserted_at],
        limit: 1
      )
    )
  end

  @doc """
  Inserts a new snapshot if the incoming `ViewScreen` differs from the most
  recently stored one. Compares `current_player_name`, `players`, `eliminated`,
  `winners`, `finished`, and `fogged`.

  Returns `{:ok, snapshot}` on insert, `{:ok, :unchanged}` when nothing has
  changed, or `{:error, changeset}` on failure.
  """
  @spec record_if_changed(RawViewScreen.t()) ::
          {:ok, WargearViewScreenDb.t()} | {:ok, :unchanged} | {:error, Ecto.Changeset.t()}
  def record_if_changed(%RawViewScreen{} = raw) do
    incoming = WargearViewScreenDb.from_view_screen(raw)

    case get_latest(incoming.game_id) do
      nil ->
        Repo.insert(incoming)

      existing ->
        if changed?(existing, incoming), do: Repo.insert(incoming), else: {:ok, :unchanged}
    end
  end

  @doc "Deletes snapshots older than `days` days. Used by the pruning job."
  @spec prune(pos_integer()) :: {non_neg_integer(), nil}
  def prune(days \\ 90) do
    cutoff = DateTime.utc_now() |> DateTime.add(-days * 86_400)
    Repo.delete_all(from(v in WargearViewScreenDb, where: v.inserted_at < ^cutoff))
  end

  defp changed?(existing, incoming) do
    existing.current_player_name != incoming.current_player_name or
      existing.players != incoming.players or
      existing.eliminated != incoming.eliminated or
      existing.winners != incoming.winners or
      existing.finished != incoming.finished or
      existing.fogged != incoming.fogged
  end
end
