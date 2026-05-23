defmodule Spitegear.GameLog.Processor do
  @moduledoc """
  Processes stored game log HTML snapshots into structured GameLogEvent records.

  ## Usage

      Processor.process_all()         # parse all snapshots
      Processor.reprocess_unrecognized()  # retry only unrecognized events
  """

  import Ecto.Query
  alias Spitegear.GameLog.Parser
  alias Spitegear.GameLogEvent
  alias Spitegear.GameLogSnapshot
  alias Spitegear.Repo

  @doc """
  Processes every stored snapshot. Idempotent — existing events are updated
  in-place (except raw_action, which never changes).
  Returns `{:ok, %{processed: n, upserted: n, unrecognized: n}}`.
  """
  def process_all do
    snapshots = Repo.all(GameLogSnapshot)

    results =
      Enum.map(snapshots, fn snapshot ->
        game_id = Integer.to_string(snapshot.game_id)
        process_snapshot(game_id, snapshot.html)
      end)

    totals =
      Enum.reduce(results, %{processed: 0, upserted: 0, unrecognized: 0}, fn
        {:ok, counts}, acc ->
          %{
            processed: acc.processed + counts.processed,
            upserted: acc.upserted + counts.upserted,
            unrecognized: acc.unrecognized + counts.unrecognized
          }

        {:error, _}, acc ->
          acc
      end)

    {:ok, totals}
  end

  @doc """
  Re-parses only events stored with event_type "unrecognized".
  Use after extending the parser with new patterns.
  Returns `{:ok, %{attempted: n, resolved: n, still_unrecognized: n}}`.
  """
  def reprocess_unrecognized do
    events =
      Repo.all(from(e in GameLogEvent, where: e.event_type == "unrecognized"))

    results =
      Enum.map(events, fn event ->
        row = %{
          action: event.raw_action,
          ad: event.attacker_dice,
          dd: event.defender_dice,
          bmod: event.battle_mod,
          al: to_string_or_nil(event.attacker_losses),
          dl: to_string_or_nil(event.defender_losses)
        }

        case Parser.parse_row(row) do
          {:ok, attrs} ->
            event
            |> GameLogEvent.changeset(attrs)
            |> Repo.update()

          {:unrecognized, _} ->
            :still_unrecognized
        end
      end)

    resolved = Enum.count(results, &match?({:ok, _}, &1))
    still = Enum.count(results, &(&1 == :still_unrecognized))

    {:ok, %{attempted: length(events), resolved: resolved, still_unrecognized: still}}
  end

  @doc """
  Second-pass: fills in `defender` and `territory_from` for `attacked` and
  `occupied` events where those fields are currently nil.

  Uses each game's own attacker names as candidate player names (longest first),
  then tries each as a prefix of the "defender+from_territory" middle section.
  Safe to re-run — only updates rows where defender is still nil.

  Returns `{:ok, %{attempted: n, filled: n, unfilled: n}}`.
  """
  def fill_defenders do
    game_ids =
      Repo.all(
        from(e in GameLogEvent,
          where:
            e.event_type in ["attacked", "occupied"] and
              is_nil(e.defender) and
              is_nil(e.territory_from),
          select: e.game_id,
          distinct: true
        )
      )

    results = Enum.map(game_ids, &fill_game_defenders/1)

    totals =
      Enum.reduce(results, %{attempted: 0, filled: 0, unfilled: 0}, fn
        {:ok, counts}, acc ->
          %{
            attempted: acc.attempted + counts.attempted,
            filled: acc.filled + counts.filled,
            unfilled: acc.unfilled + counts.unfilled
          }
      end)

    {:ok, totals}
  end

  defp fill_game_defenders(game_id) do
    player_names =
      Repo.all(
        from(e in GameLogEvent,
          where: e.game_id == ^game_id and not is_nil(e.player),
          select: e.player,
          distinct: true
        )
      )
      |> Enum.sort_by(&String.length/1, :desc)

    events =
      Repo.all(
        from(e in GameLogEvent,
          where:
            e.game_id == ^game_id and
              e.event_type in ["attacked", "occupied"] and
              is_nil(e.defender) and
              is_nil(e.territory_from)
        )
      )

    results =
      Enum.map(events, fn event ->
        case extract_defender(event.raw_action, player_names) do
          {defender, territory_from} ->
            event
            |> GameLogEvent.changeset(%{defender: defender, territory_from: territory_from})
            |> Repo.update()

          nil ->
            :unfilled
        end
      end)

    filled = Enum.count(results, &match?({:ok, _}, &1))
    unfilled = Enum.count(results, &(&1 == :unfilled))

    {:ok, %{attempted: length(events), filled: filled, unfilled: unfilled}}
  end

  # Extracts {defender, territory_from} from an attacked/occupied action string.
  #
  # Single space after verb → "attacked PlayerName TerritoryFrom >":
  #   tries each known player name as a prefix; returns {name, territory_from}.
  #
  # Double space after verb → "attacked  TerritoryFrom >" (neutral territory, no player defender):
  #   no player name matches; returns {nil, territory_from} so territory_from is still saved.
  defp extract_defender(raw_action, player_names) do
    case Regex.run(~r/(?:attacked|occupied)\s+(.+?) >/, raw_action) do
      [_, middle] ->
        Enum.find_value(player_names, &match_player_prefix(middle, &1)) ||
          {nil, nilify(String.trim(middle))}

      _ ->
        nil
    end
  end

  defp match_player_prefix(middle, name) do
    if String.starts_with?(middle, name) do
      territory_from =
        middle
        |> String.slice(String.length(name)..-1//1)
        |> String.trim()
        |> nilify()

      {name, territory_from}
    end
  end

  @doc """
  Returns counts of events grouped by event_type, sorted by count desc.
  """
  def event_type_counts do
    Repo.all(
      from(e in GameLogEvent,
        group_by: e.event_type,
        select: %{event_type: e.event_type, count: count(e.id)},
        order_by: [desc: count(e.id)]
      )
    )
  end

  @doc """
  Returns all events for a game, ordered by log_seq ascending.
  """
  def list_events(game_id) do
    Repo.all(
      from(e in GameLogEvent,
        where: e.game_id == ^game_id,
        order_by: [asc: e.log_seq]
      )
    )
  end

  @doc """
  Returns all unrecognized events, ordered by game_id and log_seq.
  """
  def list_unrecognized do
    Repo.all(
      from(e in GameLogEvent,
        where: e.event_type == "unrecognized",
        order_by: [asc: e.game_id, asc: e.log_seq]
      )
    )
  end

  @doc """
  Returns a summary: total events, unrecognized count, games processed,
  and the count of attacked/occupied events still missing a defender.
  """
  def summary do
    total = Repo.aggregate(GameLogEvent, :count)

    unrecognized =
      Repo.aggregate(from(e in GameLogEvent, where: e.event_type == "unrecognized"), :count)

    games = Repo.aggregate(from(e in GameLogEvent, select: e.game_id, distinct: true), :count)

    pending_defenders =
      Repo.aggregate(
        from(e in GameLogEvent,
          where:
            e.event_type in ["attacked", "occupied"] and
              is_nil(e.defender) and
              is_nil(e.territory_from)
        ),
        :count
      )

    %{
      total: total,
      unrecognized: unrecognized,
      games_processed: games,
      pending_defenders: pending_defenders
    }
  end

  # --- Private ---

  defp process_snapshot(game_id, html) do
    rows = parse_html(html)

    results =
      Enum.map(rows, fn row ->
        upsert_event(game_id, row)
      end)

    upserted = Enum.count(results, &match?({:ok, _}, &1))
    unrecognized = Enum.count(results, &match?({:unrecognized, _}, &1))

    {:ok, %{processed: length(rows), upserted: upserted, unrecognized: unrecognized}}
  end

  defp parse_html(html) do
    {:ok, document} = Floki.parse_document(html)

    document
    |> Floki.find("table.data tr")
    |> Enum.drop(1)
    |> Enum.map(&extract_row/1)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_row(tr) do
    cells = Floki.find(tr, "td") |> Enum.map(&Floki.text/1) |> Enum.map(&String.trim/1)

    case cells do
      [seq, timestamp, seat, action, ad, dd, bmod, al, dl, turn_id | _] ->
        %{
          log_seq: parse_int(seq),
          occurred_at: nilify(timestamp),
          seat: parse_int(seat),
          action: action,
          ad: nilify(ad),
          dd: nilify(dd),
          bmod: nilify(bmod),
          al: nilify(al),
          dl: nilify(dl),
          turn_id: parse_int(turn_id)
        }

      _ ->
        nil
    end
  end

  defp upsert_event(_game_id, %{log_seq: nil}), do: {:skip, :no_seq}

  defp upsert_event(game_id, row) do
    base = %{
      game_id: game_id,
      log_seq: row.log_seq,
      occurred_at: row.occurred_at,
      seat: row.seat,
      raw_action: row.action,
      turn_id: row.turn_id
    }

    parsed_result =
      Parser.parse_row(%{
        action: row.action,
        ad: row.ad,
        dd: row.dd,
        bmod: row.bmod,
        al: row.al,
        dl: row.dl
      })

    attrs =
      case parsed_result do
        {:ok, parsed} ->
          Map.merge(base, parsed)

        {:unrecognized, raw} ->
          Map.merge(base, %{event_type: "unrecognized", raw_action: raw})
      end

    result =
      %GameLogEvent{}
      |> GameLogEvent.changeset(attrs)
      |> Repo.insert(
        on_conflict: {:replace, mutable_fields()},
        conflict_target: [:game_id, :log_seq]
      )

    case parsed_result do
      {:unrecognized, raw} -> {:unrecognized, raw}
      _ -> result
    end
  end

  defp mutable_fields do
    ~w(occurred_at seat event_type raw_action
       player defender territory_from territory_to units
       attacker_dice defender_dice battle_mod
       attacker_losses defender_losses turn_id updated_at)a
  end

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil

  defp parse_int(s) do
    case Integer.parse(String.trim(s)) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp nilify(nil), do: nil
  defp nilify(""), do: nil
  defp nilify(s), do: s

  defp to_string_or_nil(nil), do: nil
  defp to_string_or_nil(n), do: Integer.to_string(n)
end
