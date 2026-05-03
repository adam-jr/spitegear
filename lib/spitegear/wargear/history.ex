defmodule Spitegear.Wargear.History do
  alias Spitegear.Settings

  @base_url "https://www.wargear.net/rest"

  def get(game_id) do
    api_key = Settings.get("wargear_api_key")

    with {:ok, %{body: body, status_code: 200}} <-
           HTTPoison.get(url(game_id), [], params: [api_key: api_key, format: "json"]),
         {:ok, %{"history" => %{"turn" => turns}}} <- Jason.decode(body) do
      {:ok, Enum.map(turns, & &1["@attributes"])}
    else
      {:ok, %{status_code: status}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  def latest_turn(game_id) do
    with {:ok, turns} <- get(game_id) do
      latest = Enum.max_by(turns, &String.to_integer(&1["turnid"]), fn -> nil end)
      {:ok, latest}
    end
  end

  defp url(game_id) do
    "#{@base_url}/GetHistoryUpdate/#{game_id}"
  end
end
