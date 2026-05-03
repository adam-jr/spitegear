defmodule Spitegear.Settings do
  import Ecto.Query
  alias Spitegear.{Repo, Setting}

  def get(key) do
    case Repo.get(Setting, key) do
      nil -> nil
      setting -> setting.value
    end
  end

  def put(key, value) do
    %Setting{key: key}
    |> Setting.changeset(%{value: value})
    |> Repo.insert(on_conflict: {:replace, [:value, :updated_at]}, conflict_target: :key)
  end

  def all do
    Repo.all(from s in Setting, order_by: s.key)
  end
end
