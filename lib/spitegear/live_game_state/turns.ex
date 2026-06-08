defmodule Spitegear.LiveGameState.Turns do
  @moduledoc """
  Context for reading and writing `LiveGameState.Turn` records.
  """

  import Ecto.Query

  alias Spitegear.LiveGameState.Turn
  alias Spitegear.Repo
  alias Spitegear.TurnHistory

  @type game_id :: String.t()

  @doc "Returns all turns for `game_id`, newest first by `started_at`."
  @spec list_turns(game_id()) :: [Turn.t()]
  def list_turns(game_id) do
    Repo.all(
      from(t in Turn,
        where: t.game_id == ^game_id,
        order_by: [desc: t.started_at]
      )
    )
  end

  @doc """
  Returns the currently open turn for `game_id` — the most recent row with
  `ended_at IS NULL` — or `nil` if no open turn exists.
  """
  @spec get_open_turn(game_id()) :: Turn.t() | nil
  def get_open_turn(game_id) do
    Repo.one(
      from(t in Turn,
        where: t.game_id == ^game_id and is_nil(t.ended_at),
        order_by: [desc: t.started_at],
        limit: 1
      )
    )
  end

  @doc """
  Closes `turn` by setting `ended_at` to the current UTC time. Returns the
  updated struct with `ended_at` populated.
  """
  @spec finish_turn(Turn.t()) :: {:ok, Turn.t()} | {:error, term()}
  def finish_turn(%Turn{id: id} = turn) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    Repo.update_all(from(t in Turn, where: t.id == ^id), set: [ended_at: now])
    {:ok, %{turn | ended_at: now}}
  end

  @doc """
  Inserts a new open turn for `player_name` in `game_id` with `started_at`
  set to the current UTC time and `ended_at: nil`.
  """
  @spec start_turn(game_id(), String.t()) :: {:ok, Turn.t()} | {:error, term()}
  def start_turn(game_id, player_name) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    Repo.insert(%Turn{game_id: game_id, player_name: player_name, started_at: now})
  end

  @doc """
  Records a new turn starting for `player_name`. Closes any currently open
  turn for the game first, then inserts a new row with `started_at` set to
  the current UTC time and `ended_at: nil`.
  """
  @spec record_turn_start(game_id(), String.t()) :: {:ok, Turn.t()} | {:error, term()}
  def record_turn_start(game_id, player_name) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    close_open_turn(game_id, now)
    Repo.insert(%Turn{game_id: game_id, player_name: player_name, started_at: now})
  end

  @doc """
  Returns the most recently closed turn for `game_id` — the row with the
  latest non-nil `ended_at` — or `nil` if no closed turn exists.
  """
  @spec get_last_closed_turn(game_id()) :: Turn.t() | nil
  def get_last_closed_turn(game_id) do
    Repo.one(
      from(t in Turn,
        where: t.game_id == ^game_id and not is_nil(t.ended_at),
        order_by: [desc: t.ended_at],
        limit: 1
      )
    )
  end

  @doc """
  Returns round info for `game_id` based on turns in `live_game_state_turns`.

  ## Fields

  - `current_round` — the highest turn count held by any player. Equivalent to
    the round that player is currently playing.
  - `turn_number_within_round` — how many players have reached `current_round`.
    When exactly 1, a new round just started (`new_round_starting?` is also `true`).
  - `overall_turn_number` — total turns across all players and all rounds.
  - `seat_number` — map of player name → 1-indexed seat position, ordered by
    each player's first `started_at` in the game (seat 1 goes first each round).
  - `new_round_starting?` — `true` when exactly one player is at `current_round`,
    i.e. a new round just started.
  - `turn_counts` — map of player name → total turn count (open + closed).

  Returns all-zero/empty maps when no turns exist for the game.
  """
  @type round_info :: %{
          current_round: non_neg_integer(),
          turn_number_within_round: non_neg_integer(),
          overall_turn_number: non_neg_integer(),
          seat_number: %{optional(String.t()) => pos_integer()},
          new_round_starting?: boolean(),
          turn_counts: %{optional(String.t()) => pos_integer()}
        }

  @spec round_info(game_id()) :: round_info()
  def round_info(game_id) do
    raw =
      Repo.all(
        from t in Turn,
          where: t.game_id == ^game_id,
          group_by: t.player_name,
          select: {t.player_name, count(t.id), min(t.started_at)}
      )

    if raw == [] do
      %{
        current_round: 0,
        turn_number_within_round: 0,
        overall_turn_number: 0,
        seat_number: %{},
        new_round_starting?: false,
        turn_counts: %{}
      }
    else
      turn_counts = Map.new(raw, fn {player, cnt, _} -> {player, cnt} end)

      seat_number =
        raw
        |> Enum.sort_by(fn {_, _, first_at} -> first_at end)
        |> Enum.with_index(1)
        |> Map.new(fn {{player, _, _}, seat} -> {player, seat} end)

      current_round = turn_counts |> Map.values() |> Enum.max()
      turn_number_within_round = turn_counts |> Map.values() |> Enum.count(&(&1 == current_round))
      overall_turn_number = turn_counts |> Map.values() |> Enum.sum()

      %{
        current_round: current_round,
        turn_number_within_round: turn_number_within_round,
        overall_turn_number: overall_turn_number,
        seat_number: seat_number,
        new_round_starting?: turn_number_within_round == 1,
        turn_counts: turn_counts
      }
    end
  end

  @doc """
  Runs `backfill_from_turn_history/1` for every game that has records in
  `turn_history`. Returns the total number of rows inserted across all games.

  Intended for a one-time migration. Safe to call multiple times only if
  `live_game_state_turns` has been cleared first.
  """
  @spec backfill_all_games() :: non_neg_integer()
  def backfill_all_games do
    game_ids = Repo.all(from(th in TurnHistory, select: th.game_id, distinct: true))

    Enum.reduce(game_ids, 0, fn game_id, total ->
      {count, _} = backfill_from_turn_history(game_id)
      total + count
    end)
  end

  @doc """
  Bulk-inserts `LiveGameState.Turn` rows for `game_id` by converting every
  `TurnHistory` record for that game. Intended for a one-time backfill — safe
  to call multiple times only if the table has been cleared first.

  Returns `{inserted_count, nil}`.
  """
  @spec backfill_from_turn_history(game_id()) :: {non_neg_integer(), nil}
  def backfill_from_turn_history(game_id) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    rows =
      Repo.all(
        from(th in TurnHistory,
          where: th.game_id == ^game_id,
          order_by: [asc: th.started]
        )
      )
      |> Enum.map(fn th ->
        %{
          game_id: th.game_id,
          player_name: th.player_name,
          started_at: th.started,
          ended_at: th.ended,
          reminders: 0,
          moving_announced: false,
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(Turn, rows)
  end

  defp close_open_turn(game_id, ended_at) do
    Repo.update_all(
      from(t in Turn, where: t.game_id == ^game_id and is_nil(t.ended_at)),
      set: [ended_at: ended_at]
    )
  end
end
