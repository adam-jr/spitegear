defmodule Spitegear.Repo.Migrations.AddSenderToMessageTemplates do
  use Ecto.Migration

  def change do
    alter table(:message_templates) do
      add(:sender_name, :string)
      add(:sender_icon_url, :string)
    end
  end
end
