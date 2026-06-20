defmodule Spitegear.ConsoleHistory do
  use Ecto.Schema
  import Ecto.Query
  alias Spitegear.Repo

  @limit 200

  schema "console_history" do
    field(:command, :string)
    timestamps(updated_at: false)
  end

  def list_recent do
    from(h in __MODULE__, order_by: [desc: h.inserted_at], limit: @limit, select: h.command)
    |> Repo.all()
  end

  def save(command) do
    Repo.insert!(%__MODULE__{command: command})

    keep_ids =
      from(h in __MODULE__, order_by: [desc: h.inserted_at], limit: @limit, select: h.id)

    from(h in __MODULE__, where: h.id not in subquery(keep_ids))
    |> Repo.delete_all()

    :ok
  end
end
