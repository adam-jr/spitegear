defmodule Spitegear.Wargear.History do
  alias Spitegear.Settings

  @base_url "https://www.wargear.net"

  def get(game_id) do
    api_key = Settings.get("wargear_api_key")

    with {:ok, %{body: body, status_code: 200}} <-
           HTTPoison.get(url(game_id), [], params: [api_key: api_key, format: "JSON"]),
         {:ok, %{"turns" => turns}} <- Jason.decode(body) do
      {:ok, turns}
    else
      {:ok, %{status_code: status}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  def latest_turn(game_id) do
    with {:ok, turns} <- get(game_id) do
      {:ok, turns |> Enum.max_by(& &1["turnid"], fn -> nil end)}
    end
  end

  defp url(game_id) do
    "#{@base_url}/GetHistoryUpdate/#{game_id}"
  end
end
