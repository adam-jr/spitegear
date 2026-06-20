defmodule Spitegear.Repo.Migrations.CreateConsoleHistory do
  use Ecto.Migration

  def change do
    create table(:console_history) do
      add :command, :text, null: false
      timestamps(updated_at: false)
    end
  end
end
