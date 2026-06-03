defmodule Spitegear.LiveGameState do
  @moduledoc """
  Struct and polling logic for a single active game.

  `LiveGameState` is the source of truth for what the poller knows about a
  game at any given moment. Each poll, `fetch_game_state/1` makes one HTTP
  call to the wargear.net history API, shifts the previous result into
  `prev_poll_latest_turn`, and stores the fresh result in `latest_turn`.

  Keeping both values lets `new_activity?/1` detect a turn change without
  the poller needing to carry any extra state or do any comparisons itself.
  """

  alias Spitegear.Wargear.HTTP

  @type turn :: %{String.t() => term()}

  @type t :: %__MODULE__{
          game_id: String.t() | nil,
          latest_turn: turn() | nil,
          prev_poll_latest_turn: turn() | nil
        }

  defstruct game_id: nil,
            latest_turn: nil,
            prev_poll_latest_turn: nil

  @doc """
  Returns a fresh state struct for `game_id` with no turn data yet.

      iex> state = Spitegear.LiveGameState.new("42")
      iex> {state.game_id, state.latest_turn, state.prev_poll_latest_turn}
      {"42", nil, nil}

  """
  @spec new(String.t()) :: t()
  def new(game_id), do: %__MODULE__{game_id: game_id}

  @doc """
  Fetches the latest turn from the wargear.net history API and returns an
  updated state.

  `latest_turn` is moved into `prev_poll_latest_turn` before the new value
  is stored, so callers can compare across polls without keeping extra state.
  On failure the struct is returned unchanged.
  """
  @spec fetch_game_state(t()) :: t()
  def fetch_game_state(%__MODULE__{game_id: game_id, latest_turn: current} = state) do
    case HTTP.History.latest_turn(game_id) do
      {:ok, turn} -> %{state | prev_poll_latest_turn: current, latest_turn: turn}
      _ -> state
    end
  end

  @doc """
  Returns `true` when the turn ID in `latest_turn` differs from the one in
  `prev_poll_latest_turn`, indicating activity since the last poll.

  Returns `false` on the first poll (when `prev_poll_latest_turn` is still
  `nil`) and whenever the fetch failed and the struct was not updated.

      iex> Spitegear.LiveGameState.new_activity?(Spitegear.LiveGameState.new("42"))
      false

      iex> state = %Spitegear.LiveGameState{
      ...>   game_id: "42",
      ...>   latest_turn: %{"turnid" => "2"},
      ...>   prev_poll_latest_turn: %{"turnid" => "1"}
      ...> }
      iex> Spitegear.LiveGameState.new_activity?(state)
      true

      iex> same = %Spitegear.LiveGameState{
      ...>   game_id: "42",
      ...>   latest_turn: %{"turnid" => "5"},
      ...>   prev_poll_latest_turn: %{"turnid" => "5"}
      ...> }
      iex> Spitegear.LiveGameState.new_activity?(same)
      false

  """
  @spec new_activity?(t()) :: boolean()
  def new_activity?(%__MODULE__{latest_turn: latest, prev_poll_latest_turn: prev}) do
    latest != nil && prev != nil && latest["turnid"] != prev["turnid"]
  end
end
