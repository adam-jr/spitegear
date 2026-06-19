defmodule Spitegear.GameMaps do
  @moduledoc false
  import Ecto.Query

  alias Spitegear.GameMapImage
  alias Spitegear.Repo

  @spec get(String.t()) :: GameMapImage.t() | nil
  def get(game_id) do
    Repo.one(from(m in GameMapImage, where: m.game_id == ^game_id))
  end

  @spec upsert(String.t(), binary(), String.t()) ::
          {:ok, GameMapImage.t()} | {:error, Ecto.Changeset.t()}
  def upsert(game_id, image_bytes, content_type \\ "image/png") do
    %GameMapImage{}
    |> Ecto.Changeset.change(%{
      game_id: game_id,
      image: image_bytes,
      content_type: content_type
    })
    |> Repo.insert(
      on_conflict: {:replace, [:image, :content_type, :updated_at]},
      conflict_target: :game_id
    )
  end
end
