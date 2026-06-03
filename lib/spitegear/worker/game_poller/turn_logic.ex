defmodule Spitegear.Worker.GamePoller.TurnLogic do
  @moduledoc """
  Pure turn-detection logic extracted from `GamePoller` for testability.

  All functions are side-effect free. Functions that depend on the current
  time accept an explicit `now` parameter so callers control the clock.
  """

  alias Spitegear.HTML.Player
  alias Spitegear.Turn
  alias Spitegear.Wargear.HTTP.ViewScreen

  # 3 hours
  @reminder_interval_seconds 3 * 60 * 60

  @doc """
  Returns `true` when the player shown in `view_screen` differs from the player
  recorded in `current_turn`, signalling that a new turn has started.
  """
  @spec new_turn?(%{view_screen: ViewScreen.t(), current_turn: Turn.t() | nil}) :: boolean()
  def new_turn?(%{view_screen: %ViewScreen{current_player: nil}}), do: false

  def new_turn?(%{
        current_turn: %Turn{player: %{name: prev}},
        view_screen: %ViewScreen{current_player: %Player{name: curr}}
      }) do
    prev != curr
  end

  def new_turn?(%{view_screen: %ViewScreen{current_player: %Player{}}}), do: true

  @doc """
  Returns `true` when a reminder should be sent for the active turn.

  A reminder is due when both conditions hold:
  - The last reminder was sent more than `#{@reminder_interval_seconds}` seconds ago.
  - `now` falls within waking hours in America/Chicago (07:00–23:59).
  """
  @spec reminder_due?(%{current_turn: Turn.t() | nil}, DateTime.t()) :: boolean()
  def reminder_due?(%{current_turn: %Turn{reminded: reminded_time}}, now) do
    {:ok, chicago} = DateTime.shift_zone(now, "America/Chicago")
    waking_hours? = chicago.hour >= 7 and chicago.hour < 24
    beyond_horizon? = DateTime.diff(now, reminded_time) > @reminder_interval_seconds
    waking_hours? and beyond_horizon?
  end

  def reminder_due?(_state, _now), do: false

  @doc """
  Returns the players who were skipped between `prev_idx` and `curr_idx` in
  circular turn order over a list of `n` alive players.

  Returns `[]` when either index is `nil` or when there are fewer than 2
  players (no turn order to speak of).
  """
  @spec skipped_players(
          [Player.t()],
          non_neg_integer(),
          non_neg_integer() | nil,
          non_neg_integer() | nil
        ) :: [Player.t()]
  def skipped_players(_players, n, prev_idx, curr_idx)
      when is_nil(prev_idx) or is_nil(curr_idx) or n < 2,
      do: []

  def skipped_players(players, n, prev_idx, curr_idx) do
    Stream.iterate(rem(prev_idx + 1, n), &rem(&1 + 1, n))
    |> Enum.take_while(&(&1 != curr_idx))
    |> Enum.map(&Enum.at(players, &1))
  end
end
