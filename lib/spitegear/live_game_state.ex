defmodule Spitegear.LiveGameState do
  @moduledoc false

  alias Spitegear.Wargear.HTTP.History

  @doc "Fetches the latest turn for `game_id` from the wargear.net history API."
  @spec fetch_latest_turn(String.t()) :: {:ok, map()} | {:error, term()}
  def fetch_latest_turn(game_id) do
    History.latest_turn(game_id)
  end
end
