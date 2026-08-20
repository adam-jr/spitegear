defmodule Spitegear.MessageTemplate do
  use Ecto.Schema
  import Ecto.Changeset

  schema "message_templates" do
    field(:key, :string)
    field(:template, :string)
    field(:game_id, :string)
    field(:sender_name, :string)
    field(:sender_icon_url, :string)

    timestamps()
  end

  def changeset(template, attrs) do
    template
    |> cast(attrs, [:key, :template, :game_id, :sender_name, :sender_icon_url])
    |> validate_required([:key, :template])
  end
end
