defmodule Spitegear.GameLogSnapshot do
  use Ecto.Schema
  import Ecto.Changeset

  schema "game_log_snapshots" do
    field(:game_id, :integer)
    field(:html, :string)
    field(:fetched_at, :utc_datetime_usec)

    timestamps()
  end

  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [:game_id, :html, :fetched_at])
    |> validate_required([:game_id, :html, :fetched_at])
    |> unique_constraint(:game_id)
  end
end
