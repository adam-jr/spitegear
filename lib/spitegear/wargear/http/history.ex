defmodule Spitegear.Wargear.HTTP.History do
  @moduledoc false
  alias Spitegear.Settings

  @base_url "https://www.wargear.net/rest"

  def get(game_id) do
    api_key = Settings.get("wargear_api_key")

    with {:ok, %{status: 200, body: %{"history" => %{"turn" => turns}}}} <-
           Req.get(url(game_id), params: [api_key: api_key, format: "json"]) do
      {:ok, Enum.map(turns, & &1["@attributes"])}
    else
      {:ok, %{status: status}} -> {:error, {:http, status}}
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
