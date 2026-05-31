defmodule Spitegear.GameLog.Stats do
  @moduledoc """
  Aggregate stats computed over processed GameLogEvent records.

  Functions here are pure reducers over event streams — no side effects.
  Each stat function fetches events for a game and folds over them.
  """

  import Ecto.Query
  alias Spitegear.GameLogEvent
  alias Spitegear.Repo

  # Event types where the player gained units equal to the `units` field.
  @positive_unit_events ~w(
    received_bonus
    received_units
    received_elimination_bonus
    factory_produced
    traded_cards
    assimilated
  )

  @doc """
  Returns a per-player net unit series for a game, keyed by player name.

  Each value is a list of `%{seq: integer, net_units: integer}` in ascending
  seq order, containing one entry per log_seq where that player's net count
  changed.

  Positive events: #{Enum.join(@positive_unit_events, ", ")}.
  Negative events: attacker_losses (when player attacked), defender_losses
  (when player defended). Nil units/losses produce no delta.

  ## Example

      %{
        "ZachClash"          => [%{seq: 3, net_units: 5}, %{seq: 9, net_units: 3}],
        "pants off vant hof" => [%{seq: 5, net_units: 4}, ...]
      }
  """
  def net_units_over_time(game_id) do
    events =
      Repo.all(
        from(e in GameLogEvent,
          where: e.game_id == ^game_id,
          order_by: [asc: e.log_seq]
        )
      )

    cutoff = setup_cutoff(events)

    # Aggregate all setup placed_units into a single starting point per player
    # at the cutoff seq, so the chart begins cleanly after setup completes.
    setup_deltas =
      if cutoff > 0 do
        events
        |> Enum.take_while(&(&1.log_seq < cutoff))
        |> Enum.flat_map(&setup_placed_delta/1)
        |> Enum.group_by(& &1.player)
        |> Enum.map(fn {player, deltas} ->
          total = Enum.sum(Enum.map(deltas, & &1.delta))
          %{player: player, seq: cutoff, delta: total}
        end)
      else
        []
      end

    game_deltas =
      events
      |> Enum.drop_while(&(&1.log_seq < cutoff))
      |> Enum.flat_map(&event_to_deltas/1)

    (setup_deltas ++ game_deltas)
    |> build_series()
  end

  @doc """
  Returns log-derived summary stats for a game:
    - `max_seq`    — highest log_seq in the game
    - `turn_count` — number of started_turn events
  """
  def game_log_summary(game_id) do
    max_seq =
      Repo.one(from(e in GameLogEvent, where: e.game_id == ^game_id, select: max(e.log_seq))) || 0

    turn_count =
      Repo.one(
        from(e in GameLogEvent,
          where: e.game_id == ^game_id and e.event_type == "started_turn",
          select: count(e.id)
        )
      ) || 0

    %{max_seq: max_seq, turn_count: turn_count}
  end

  @doc """
  Returns a per-player placement score for a game, keyed by player name.

  The score is the area under each player's net-units curve — net_units
  integrated over log_seq from the end of the setup phase to the last event
  in the game. Higher means the player held more units for more of the game.

  ## Example

      %{
        "ZachClash"          => 42180,
        "pants off vant hof" => 31450
      }
  """
  def placement_scores(game_id) do
    series = net_units_over_time(game_id)

    if map_size(series) == 0 do
      %{}
    else
      last_seq =
        Repo.one(from(e in GameLogEvent, where: e.game_id == ^game_id, select: max(e.log_seq))) ||
          0

      Map.new(series, fn {player, points} ->
        {player, integrate(points, last_seq)}
      end)
    end
  end

  # --- Private ---

  # The "setup" event ("Initial board setup complete") marks the end of the setup
  # phase. Falls back to the first started_turn if the setup event is absent.
  # Returns 0 if neither is found — no setup phase detected.
  #
  # Note: game_started fires before setup begins (players joining the lobby),
  # so it is NOT used as a cutoff.
  defp setup_cutoff(events) do
    Enum.find_value(events, fn e ->
      if e.event_type == "setup", do: e.log_seq, else: nil
    end) ||
      Enum.find_value(events, fn e ->
        if e.event_type == "started_turn", do: e.log_seq, else: nil
      end) ||
      0
  end

  # Setup phase only: placed_units count as the player's starting units.
  # "Neutral" player placements are skipped (neutral territories are not owned).
  # In-game placed_units (after setup is complete) are excluded — those units
  # were already counted via received_units/received_bonus.
  defp setup_placed_delta(%GameLogEvent{
         event_type: "placed_units",
         player: p,
         units: u,
         log_seq: s
       })
       when not is_nil(p) and p != "Neutral" and not is_nil(u) do
    [%{player: p, seq: s, delta: u}]
  end

  defp setup_placed_delta(_), do: []

  defp build_series(deltas) do
    deltas
    |> Enum.group_by(& &1.player)
    |> Map.new(fn {player, player_deltas} ->
      series =
        player_deltas
        |> Enum.scan(0, fn %{delta: d}, acc -> acc + d end)
        |> Enum.zip(player_deltas)
        |> Enum.map(fn {net, %{seq: s}} -> %{seq: s, net_units: net} end)

      {player, series}
    end)
  end

  # Positive: player received/produced/captured units
  defp event_to_deltas(%GameLogEvent{event_type: t, player: p, units: u, log_seq: s})
       when t in @positive_unit_events and not is_nil(p) and not is_nil(u) do
    [%{player: p, seq: s, delta: u}]
  end

  # Combat: attacker and/or defender lost units; both sides independent
  defp event_to_deltas(%GameLogEvent{
         event_type: "attacked",
         player: p,
         defender: d,
         attacker_losses: al,
         defender_losses: dl,
         log_seq: s
       }) do
    attacker =
      if not is_nil(p) and not is_nil(al), do: [%{player: p, seq: s, delta: -al}], else: []

    defender =
      if not is_nil(d) and not is_nil(dl), do: [%{player: d, seq: s, delta: -dl}], else: []

    attacker ++ defender
  end

  # Reserve units captured on elimination: gain for capturer, loss for eliminated player
  defp event_to_deltas(%GameLogEvent{
         event_type: "captured_reserve_units",
         player: p,
         defender: d,
         units: u,
         log_seq: s
       }) do
    capturer =
      if not is_nil(p) and not is_nil(u), do: [%{player: p, seq: s, delta: u}], else: []

    eliminated =
      if not is_nil(d) and not is_nil(u), do: [%{player: d, seq: s, delta: -u}], else: []

    capturer ++ eliminated
  end

  # Factory destroyed: units on that territory are lost
  defp event_to_deltas(%GameLogEvent{
         event_type: "factory_destroyed",
         player: p,
         units: u,
         log_seq: s
       })
       when not is_nil(p) and not is_nil(u) do
    [%{player: p, seq: s, delta: -u}]
  end

  # Discarded units are a genuine unit loss
  defp event_to_deltas(%GameLogEvent{
         event_type: "discarded_units",
         player: p,
         units: u,
         log_seq: s
       })
       when not is_nil(p) and not is_nil(u) do
    [%{player: p, seq: s, delta: -u}]
  end

  defp event_to_deltas(_), do: []

  # Compute the area under a step-function series.
  # Each point holds net_units from its seq until the next point's seq;
  # the last point holds until last_seq.
  defp integrate([], _last_seq), do: 0

  defp integrate(points, last_seq) do
    next_seqs = points |> Enum.map(& &1.seq) |> tl() |> Kernel.++([last_seq])

    points
    |> Enum.zip(next_seqs)
    |> Enum.map(fn {%{net_units: n, seq: s}, next_s} -> n * (next_s - s) end)
    |> Enum.sum()
  end
end
