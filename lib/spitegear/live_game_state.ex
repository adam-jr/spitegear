defmodule Spitegear.LiveGameState do
  @moduledoc false

  alias Spitegear.Wargear.HTTP.History

  @type t :: %__MODULE__{}

  defstruct game_id: nil,
            latest_turn: nil,
            prev_poll_latest_turn: nil

  @doc "Returns a fresh state struct for `game_id`."
  @spec new(String.t()) :: t()
  def new(game_id), do: %__MODULE__{game_id: game_id}

  @doc """
  Fetches the latest turn from the wargear.net history API and returns an
  updated state. The previous value of `latest_turn` is moved into
  `prev_poll_latest_turn` so callers can detect change between polls.
  On failure the struct is returned unchanged.
  """
  @spec fetch_game_state(t()) :: t()
  def fetch_game_state(%__MODULE__{game_id: game_id, latest_turn: current} = state) do
    case History.latest_turn(game_id) do
      {:ok, turn} -> %{state | prev_poll_latest_turn: current, latest_turn: turn}
      _ -> state
    end
  end

  @doc "Returns `true` when the latest turn differs from the previous poll."
  @spec new_activity?(t()) :: boolean()
  def new_activity?(%__MODULE__{latest_turn: latest, prev_poll_latest_turn: prev}) do
    latest != nil && prev != nil && latest["turnid"] != prev["turnid"]
  end
end
