defmodule Spitegear.Repo.Migrations.CreateMessageTemplates do
  use Ecto.Migration

  def change do
    create table(:message_templates) do
      add :key, :string, null: false
      add :template, :text, null: false
      add :game_id, :string

      timestamps()
    end

    create unique_index(:message_templates, [:key],
             where: "game_id IS NULL",
             name: :message_templates_global_key_index
           )

    create unique_index(:message_templates, [:key, :game_id],
             where: "game_id IS NOT NULL",
             name: :message_templates_game_key_index
           )
  end
end
