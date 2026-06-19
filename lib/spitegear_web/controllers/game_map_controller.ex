defmodule SpitegearWeb.GameMapController do
  use SpitegearWeb, :controller

  alias Spitegear.GameMaps

  def show(conn, %{"game_id" => game_id}) do
    case GameMaps.get(game_id) do
      nil ->
        send_resp(conn, 404, "")

      map ->
        conn
        |> put_resp_content_type(map.content_type)
        |> put_resp_header("cache-control", "public, max-age=300")
        |> send_resp(200, map.image)
    end
  end
end
