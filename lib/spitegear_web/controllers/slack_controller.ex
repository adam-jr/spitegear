defmodule SpitegearWeb.SlackController do
  use SpitegearWeb, :controller

  require Logger

  def handle_events(conn, %{"type" => "url_verification", "challenge" => challenge}) do
    json(conn, %{challenge: challenge})
  end

  def handle_events(conn, %{"type" => "event_callback", "event" => event}) do
    Logger.info("Received event: #{inspect(event)}")
    send_resp(conn, 200, "ok")
  end

  def handle_events(conn, _params) do
    send_resp(conn, 400, "Bad Request")
  end
end
