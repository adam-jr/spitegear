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
