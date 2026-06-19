defmodule Spitegear.LiveGameState.WargearViewScreenDb do
  @moduledoc """
  Append-only snapshot of a parsed wargear.net ViewScreen as observed during
  live game tracking.

  A new row is written only when the screen content changes — i.e. when the
  active player, player list, eliminations, winners, or fog state differs from
  the most recently stored snapshot for the game. Unchanged polls produce no
  new row.

  `players` is stored as a list of maps with `"name"` and `"slack_name"` keys.
  `eliminated` and `winners` are stored as lists of player name strings.
  """

  use Ecto.Schema

  alias Spitegear.Wargear.HTTP.ViewScreen, as: RawViewScreen

  @type t :: %__MODULE__{}

  @timestamps_opts [type: :utc_datetime]
  schema "live_game_state_view_screens" do
    field(:game_id, :string)
    field(:game_name, :string)
    field(:board_name, :string)
    field(:created, :string)
    field(:finished, :string)
    field(:current_player_name, :string)
    field(:players, {:array, :map})
    field(:eliminated, {:array, :string})
    field(:winners, {:array, :string})
    field(:fogged, :boolean, default: false)
    field(:board_image_url, :string)

    timestamps()
  end

  @doc "Builds a `WargearViewScreenDb` from a parsed `ViewScreen` struct."
  @spec from_view_screen(RawViewScreen.t()) :: t()
  def from_view_screen(%RawViewScreen{} = vs) do
    %__MODULE__{
      game_id: vs.game_id,
      game_name: vs.game_name,
      board_name: vs.board_name,
      created: vs.created,
      finished: vs.finished,
      current_player_name: vs.current_player && vs.current_player.name,
      players:
        Enum.map(
          vs.players,
          &%{"name" => &1.name, "slack_name" => &1.slack_name, "color" => &1.color}
        ),
      eliminated: Enum.map(vs.eliminated, & &1.name),
      winners: Enum.map(vs.winners, & &1.name),
      fogged: vs.fogged?,
      board_image_url: vs.board_image_url
    }
  end
end
