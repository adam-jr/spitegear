defmodule Spitegear.Repo.Migrations.ChangeSettingsValueToText do
  use Ecto.Migration

  def change do
    alter table(:settings) do
      modify :value, :text
    end
  end
end
