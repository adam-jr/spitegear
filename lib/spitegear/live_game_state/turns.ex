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
  Returns round info for `game_id` based on completed turns in
  `live_game_state_turns`.

  `max_played_round` is the highest number of completed turns held by any
  single player — equivalent to the round number that player is currently on.
  `new_round_starting?` is true when exactly one player is at that maximum,
  meaning they are the only one who has started the new round so far.

  Returns `%{max_played_round: 0, new_round_starting?: false, turn_counts: %{}}` when no
  completed turns exist.

  `turn_counts` is a map of player name → completed turn count, useful for
  computing a player's current round number and their position within that round.
  """
  @type round_info :: %{
          max_played_round: non_neg_integer(),
          new_round_starting?: boolean(),
          turn_counts: %{optional(String.t()) => pos_integer()}
        }

  @spec round_info(game_id()) :: round_info()
  def round_info(game_id) do
    turn_counts =
      Repo.all(
        from(t in Turn,
          where: t.game_id == ^game_id,
          select: t.player_name
        )
      )
      |> Enum.frequencies()

    if map_size(turn_counts) == 0 do
      %{max_played_round: 0, new_round_starting?: false, turn_counts: %{}}
    else
      max_played_round = turn_counts |> Map.values() |> Enum.max()

      new_round_starting? =
        turn_counts
        |> Map.values()
        |> Enum.count(&(&1 == max_played_round))
        |> Kernel.==(1)

      %{
        max_played_round: max_played_round,
        new_round_starting?: new_round_starting?,
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
