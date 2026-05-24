defmodule SpitegearWeb.PageController do
  use SpitegearWeb, :controller
  alias Spitegear.Games

  def home(conn, _params) do
    active_games =
      Games.list_active_games()
      |> Enum.map(fn game ->
        turn = Games.get_current_turn(game.game_id)
        statuses = Games.list_player_statuses(game.game_id)
        alive = Enum.filter(statuses, & &1.alive)

        %{game: game, current_turn: turn, alive_players: alive}
      end)

    finished_games = Games.list_finished_games() |> Enum.take(10)

    render(conn, :home, layout: false, active_games: active_games, finished_games: finished_games)
  end
end
