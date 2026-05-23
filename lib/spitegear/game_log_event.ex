defmodule Spitegear.GameLogEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @fields ~w(game_id log_seq occurred_at seat player_name event_type raw_action
             attacker defender territory_from territory_to units
             attacker_dice defender_dice battle_mod
             attacker_losses defender_losses turn_id)a

  schema "game_log_events" do
    field(:game_id, :string)
    field(:log_seq, :integer)
    field(:occurred_at, :string)
    field(:seat, :integer)
    field(:player_name, :string)
    field(:event_type, :string)
    field(:raw_action, :string)
    field(:attacker, :string)
    field(:defender, :string)
    field(:territory_from, :string)
    field(:territory_to, :string)
    field(:units, :integer)
    field(:attacker_dice, :string)
    field(:defender_dice, :string)
    field(:battle_mod, :string)
    field(:attacker_losses, :integer)
    field(:defender_losses, :integer)
    field(:turn_id, :integer)

    timestamps()
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, @fields)
    |> validate_required([:game_id, :log_seq, :event_type, :raw_action])
    |> unique_constraint([:game_id, :log_seq])
  end
end
