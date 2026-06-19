defmodule Spitegear.GameMapImage do
  @moduledoc false
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @timestamps_opts [type: :utc_datetime]
  schema "game_map_images" do
    field(:game_id, :string)
    field(:image, :binary)
    field(:content_type, :string, default: "image/png")
    belongs_to(:turn, Spitegear.LiveGameState.Turn)

    timestamps()
  end
end
