defmodule Spitegear.GamePoller.Turn do
  @moduledoc """
  Embedded schema for turns
  """
  use Ecto.Schema

  @primary_key false
  embedded_schema do
    field(:player, :any, virtual: true)
    field(:reminded_at, :utc_datetime_usec)
    field(:reminders, :integer, default: 0)
  end
end
