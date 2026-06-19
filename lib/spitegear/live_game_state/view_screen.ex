defmodule Spitegear.LiveGameState.ViewScreen do
  @moduledoc """
  A rich view-screen snapshot reconstructed from a stored `WargearViewScreenDb`
  record, with full `HTML.Player` structs (including boolean state fields)
  rather than bare player maps.

  Mirrors the shape of `Wargear.HTTP.ViewScreen` so callers can work with both
  interchangeably, but is sourced from the database rather than a live HTTP fetch.
  """

  alias Spitegear.HTML.Player
  alias Spitegear.LiveGameState.WargearViewScreenDb

  @type t :: %__MODULE__{
          game_id: String.t() | nil,
          game_name: String.t() | nil,
          board_name: String.t() | nil,
          created: String.t() | nil,
          finished: String.t() | nil,
          board_image_url: String.t() | nil,
          players: [Player.t()],
          current_player: Player.t() | nil,
          current_player_name: String.t() | nil,
          eliminated: [Player.t()],
          winners: [Player.t()],
          fogged?: boolean(),
          next_card: String.t() | nil
        }

  defstruct game_id: nil,
            game_name: nil,
            board_name: nil,
            created: nil,
            finished: nil,
            board_image_url: nil,
            players: [],
            current_player: nil,
            current_player_name: nil,
            eliminated: [],
            winners: [],
            fogged?: false,
            next_card: nil

  @doc """
  Reconstructs a `ViewScreen` from a `WargearViewScreenDb` record,
  restoring full `Player` structs with their boolean state fields.
  """
  @spec from_db(WargearViewScreenDb.t()) :: t()
  def from_db(%WargearViewScreenDb{} = db) do
    eliminated_names = MapSet.new(db.eliminated || [])
    winner_names = MapSet.new(db.winners || [])

    players =
      (db.players || [])
      |> Enum.with_index(1)
      |> Enum.map(fn {p, seat} ->
        name = p["name"]

        %Player{
          name: name,
          slack_name: p["slack_name"],
          color: p["color"],
          seat_number: seat,
          current_turn?: name == db.current_player_name,
          eliminated?: MapSet.member?(eliminated_names, name),
          winner?: MapSet.member?(winner_names, name),
          fogged?: db.fogged
        }
      end)

    %__MODULE__{
      game_id: db.game_id,
      game_name: db.game_name,
      board_name: db.board_name,
      created: db.created,
      finished: db.finished,
      board_image_url: db.board_image_url,
      players: players,
      current_player: Enum.find(players, & &1.current_turn?),
      current_player_name: db.current_player_name,
      eliminated: Enum.filter(players, & &1.eliminated?),
      winners: Enum.filter(players, & &1.winner?),
      fogged?: db.fogged,
      next_card: db.next_card
    }
  end
end
