defmodule SpitegearWeb.PingController do
  use SpitegearWeb, :controller

  def ping(conn, _params) do
    send_resp(conn, 200, "pong")
  end
end
