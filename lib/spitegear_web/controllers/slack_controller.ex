defmodule SpitegearWeb.SlackController do
  use SpitegearWeb, :controller

  def handle_events(conn, %{"type" => "url_verification", "challenge" => challenge}) do
    json(conn, %{challenge: challenge})
  end

  def handle_events(conn, %{"type" => "event_callback", "event" => event}) do
    # Handle the event here. For example, log the event:
    IO.inspect(event, label: "Received Slack event")

    # Optionally, you can forward the event to an external endpoint:
    # HTTPoison.post("https://external-api.example.com/endpoint", Jason.encode!(event), [{"Content-Type", "application/json"}])

    send_resp(conn, 200, "ok")
  end

  def handle_events(conn, _params) do
    send_resp(conn, 400, "Bad Request")
  end
end
