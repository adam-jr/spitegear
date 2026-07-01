defmodule Spitegear.GameMaps do
  @moduledoc false
  import Ecto.Query

  alias Spitegear.GameMapImage
  alias Spitegear.Repo

  @spec get(String.t()) :: GameMapImage.t() | nil
  def get(game_id) do
    Repo.one(
      from(m in GameMapImage,
        where: m.game_id == ^game_id,
        order_by: [desc: m.inserted_at],
        limit: 1
      )
    )
  end

  @spec upsert(String.t(), integer() | nil, binary(), String.t()) ::
          {:ok, GameMapImage.t()} | {:error, Ecto.Changeset.t()}
  def upsert(game_id, turn_id, image_bytes, content_type \\ "image/png")

  def upsert(game_id, nil, image_bytes, content_type) do
    %GameMapImage{}
    |> Ecto.Changeset.change(%{
      game_id: game_id,
      turn_id: nil,
      image: image_bytes,
      content_type: content_type
    })
    |> Repo.insert(
      on_conflict: {:replace, [:image, :content_type, :updated_at]},
      conflict_target: {:unsafe_fragment, "(game_id) WHERE turn_id IS NULL"}
    )
  end

  def upsert(game_id, turn_id, image_bytes, content_type) do
    %GameMapImage{}
    |> Ecto.Changeset.change(%{
      game_id: game_id,
      turn_id: turn_id,
      image: image_bytes,
      content_type: content_type
    })
    |> Repo.insert(
      on_conflict: {:replace, [:image, :content_type, :updated_at]},
      conflict_target: {:unsafe_fragment, "(game_id, turn_id) WHERE turn_id IS NOT NULL"}
    )
  end
end
