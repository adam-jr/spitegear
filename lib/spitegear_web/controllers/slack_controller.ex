defmodule SpitegearWeb.SlackController do
  use SpitegearWeb, :controller

  require Logger

  def handle_events(conn, %{"type" => "url_verification", "challenge" => challenge}) do
    json(conn, %{challenge: challenge})
  end

  def handle_events(conn, %{"type" => "event_callback", "event" => event}) do
    Logger.info("Received event: #{inspect(event)}")

    case extract_game_id(event) do
      {:ok, game_id} ->
        Spitegear.PubSub.msg(:spitegear, "Starting game ##{game_id}")
        start_child(game_id)

      _ ->
        nil
    end

    send_resp(conn, 200, "ok")
  end

  def handle_events(conn, _params) do
    send_resp(conn, 400, "Bad Request")
  end

  defp start_child(game_id) do
    DynamicSupervisor.start_child(
      GameSupervisor,
      Spitegear.Worker.GamePoller.child_spec(game_id: game_id)
    )
  end

  @game_url_pattern ~r|wargear\.net/games/join/(\d+)|
  defp extract_game_id(%{"text" => text}) do
    case Regex.run(@game_url_pattern, text) do
      [_, game_id] -> {:ok, game_id}
      _ -> :error
    end
  end
end
