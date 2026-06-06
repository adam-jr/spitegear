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
    game_id
    |> enriched_net_units_series()
    |> Map.new(fn {player, points} ->
      {player, Enum.map(points, &Map.take(&1, [:seq, :net_units]))}
    end)
  end

  @doc """
  Like `net_units_over_time/1` but each point also carries the log event that
  caused the change:

      %{seq: 42, net_units: 7, event_type: "attacked", source_player: "dandodd", defender: "Ky..."}

  Used by the admin chart so tooltips can display the action behind each dot.
  """
  def enriched_net_units_series(game_id) do
    events =
      Repo.all(
        from(e in GameLogEvent,
          where: e.game_id == ^game_id,
          order_by: [asc: e.log_seq]
        )
      )

    cutoff = setup_cutoff(events)

    setup_deltas =
      if cutoff > 0 do
        events
        |> Enum.take_while(&(&1.log_seq < cutoff))
        |> Enum.flat_map(&setup_placed_delta/1)
        |> Enum.group_by(& &1.player)
        |> Enum.map(fn {player, deltas} ->
          total = Enum.sum(Enum.map(deltas, & &1.delta))

          %{
            player: player,
            seq: cutoff,
            delta: total,
            event_type: "setup",
            source_player: nil,
            defender: nil
          }
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

  @doc """
  Returns a per-player cumulative series of units received (gains only), keyed
  by player name. Same point shape as `enriched_net_units_series/1`.

  Includes setup `placed_units` aggregated at the cutoff seq plus all
  post-setup positive unit events (bonuses, production, card trades, etc.).
  """
  def units_received_series(game_id) do
    events =
      Repo.all(
        from(e in GameLogEvent,
          where: e.game_id == ^game_id,
          order_by: [asc: e.log_seq]
        )
      )

    cutoff = setup_cutoff(events)

    setup_deltas =
      if cutoff > 0 do
        events
        |> Enum.take_while(&(&1.log_seq < cutoff))
        |> Enum.flat_map(&setup_placed_delta/1)
        |> Enum.group_by(& &1.player)
        |> Enum.map(fn {player, deltas} ->
          total = Enum.sum(Enum.map(deltas, & &1.delta))

          %{
            player: player,
            seq: cutoff,
            delta: total,
            event_type: "setup",
            source_player: nil,
            defender: nil
          }
        end)
      else
        []
      end

    game_deltas =
      events
      |> Enum.drop_while(&(&1.log_seq < cutoff))
      |> Enum.flat_map(&received_delta/1)

    (setup_deltas ++ game_deltas)
    |> build_series()
  end

  @doc """
  Returns a per-player cumulative series of enemy units killed, keyed by player
  name. Same point shape as `enriched_net_units_series/1`.

  A "kill" is counted whenever a player's attack causes `defender_losses` on
  the opposing player.
  """
  def units_killed_series(game_id) do
    Repo.all(
      from(e in GameLogEvent,
        where: e.game_id == ^game_id,
        order_by: [asc: e.log_seq]
      )
    )
    |> Enum.flat_map(&kills_delta/1)
    |> build_series()
  end

  @doc """
  Returns a per-player cumulative luck ratio series, keyed by player name.
  Same point shape as `enriched_net_units_series/1`.

  For each attack a player makes, the delta is `defender_losses - attacker_losses`.
  A positive cumulative value means the player has lost fewer units than they've
  inflicted overall; negative means the reverse. Can go below zero.
  """
  def luck_ratio_series(game_id) do
    Repo.all(
      from(e in GameLogEvent,
        where: e.game_id == ^game_id,
        order_by: [asc: e.log_seq]
      )
    )
    |> Enum.flat_map(&luck_delta/1)
    |> build_series()
  end

  @doc """
  Returns a per-player cumulative series of attacker dice received, keyed by
  player name. Same point shape as `enriched_net_units_series/1`.

  For each attack directed at a player, the delta is the number of dice the
  attacker rolled (parsed from the `attacker_dice` field), used as a proxy
  for attacking force size.
  """
  def attacks_received_series(game_id) do
    Repo.all(
      from(e in GameLogEvent,
        where: e.game_id == ^game_id,
        order_by: [asc: e.log_seq]
      )
    )
    |> Enum.flat_map(&attacks_received_delta/1)
    |> build_series()
  end

  @doc """
  Returns a per-player cumulative count of "jormp jomps" received, keyed by
  player name. Same point shape as `enriched_net_units_series/1`.

  A jormp jomp occurs when an attacker rolls 3 dice and suffers 2 losses while
  the defender loses 0. The attacking player receives the jormp jomp — they got
  the short end of the stick.
  """
  def jormp_jomps_received_series(game_id) do
    Repo.all(
      from(e in GameLogEvent,
        where: e.game_id == ^game_id,
        order_by: [asc: e.log_seq]
      )
    )
    |> Enum.flat_map(&jormp_received_delta/1)
    |> build_series()
  end

  @doc """
  Returns a per-player cumulative count of "jormp jomps" delivered, keyed by
  player name. Same point shape as `enriched_net_units_series/1`.

  A jormp jomp is delivered by the defending player when the attacker rolls
  3 dice and suffers 2 losses with 0 defender losses. The defender gets credit
  for delivering the jormp jomp.
  """
  def jormp_jomps_delivered_series(game_id) do
    Repo.all(
      from(e in GameLogEvent,
        where: e.game_id == ^game_id,
        order_by: [asc: e.log_seq]
      )
    )
    |> Enum.flat_map(&jormp_delivered_delta/1)
    |> build_series()
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
        |> Enum.map(fn {net, %{seq: s, event_type: et, source_player: sp, defender: defender}} ->
          %{seq: s, net_units: net, event_type: et, source_player: sp, defender: defender}
        end)

      {player, series}
    end)
  end

  # Positive: player received/produced/captured units
  defp event_to_deltas(%GameLogEvent{event_type: t, player: p, units: u, log_seq: s})
       when t in @positive_unit_events and not is_nil(p) and not is_nil(u) do
    [%{player: p, seq: s, delta: u, event_type: t, source_player: p, defender: nil}]
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
      if not is_nil(p) and not is_nil(al),
        do: [
          %{player: p, seq: s, delta: -al, event_type: "attacked", source_player: p, defender: d}
        ],
        else: []

    defender =
      if not is_nil(d) and not is_nil(dl),
        do: [
          %{player: d, seq: s, delta: -dl, event_type: "attacked", source_player: p, defender: d}
        ],
        else: []

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
      if not is_nil(p) and not is_nil(u),
        do: [
          %{
            player: p,
            seq: s,
            delta: u,
            event_type: "captured_reserve_units",
            source_player: p,
            defender: d
          }
        ],
        else: []

    eliminated =
      if not is_nil(d) and not is_nil(u),
        do: [
          %{
            player: d,
            seq: s,
            delta: -u,
            event_type: "captured_reserve_units",
            source_player: p,
            defender: d
          }
        ],
        else: []

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
    [
      %{
        player: p,
        seq: s,
        delta: -u,
        event_type: "factory_destroyed",
        source_player: p,
        defender: nil
      }
    ]
  end

  # Discarded units are a genuine unit loss
  defp event_to_deltas(%GameLogEvent{
         event_type: "discarded_units",
         player: p,
         units: u,
         log_seq: s
       })
       when not is_nil(p) and not is_nil(u) do
    [
      %{
        player: p,
        seq: s,
        delta: -u,
        event_type: "discarded_units",
        source_player: p,
        defender: nil
      }
    ]
  end

  defp event_to_deltas(_), do: []

  # Positive unit events only (for units_received_series).
  defp received_delta(%GameLogEvent{event_type: t, player: p, units: u, log_seq: s})
       when t in @positive_unit_events and not is_nil(p) and not is_nil(u) do
    [%{player: p, seq: s, delta: u, event_type: t, source_player: p, defender: nil}]
  end

  defp received_delta(_), do: []

  # Kills: defender_losses attributed to the attacker (for units_killed_series).
  defp kills_delta(%GameLogEvent{
         event_type: "attacked",
         player: p,
         defender: d,
         defender_losses: dl,
         log_seq: s
       })
       when not is_nil(p) and not is_nil(dl) and dl > 0 do
    [%{player: p, seq: s, delta: dl, event_type: "attacked", source_player: p, defender: d}]
  end

  defp kills_delta(_), do: []

  # Luck ratio: (defender_losses - attacker_losses) per attack, attributed to attacker.
  defp luck_delta(%GameLogEvent{
         event_type: "attacked",
         player: p,
         defender: d,
         attacker_losses: al,
         defender_losses: dl,
         log_seq: s
       })
       when not is_nil(p) and not is_nil(al) and not is_nil(dl) do
    [%{player: p, seq: s, delta: dl - al, event_type: "attacked", source_player: p, defender: d}]
  end

  defp luck_delta(_), do: []

  # Attacks received: attacker dice count directed at the defender per attack event.
  defp attacks_received_delta(%GameLogEvent{
         event_type: "attacked",
         player: p,
         defender: d,
         attacker_dice: ad,
         log_seq: s
       })
       when not is_nil(d) do
    dice_count = if is_nil(ad) or ad == "", do: 1, else: length(String.split(ad, ","))

    [
      %{
        player: d,
        seq: s,
        delta: dice_count,
        event_type: "attacked",
        source_player: p,
        defender: d
      }
    ]
  end

  defp attacks_received_delta(_), do: []

  # True when an attack with exactly 3 dice results in 2 attacker losses and 0 defender losses.
  defp jormp_jomp?(%GameLogEvent{
         event_type: "attacked",
         attacker_dice: ad,
         attacker_losses: 2,
         defender_losses: 0
       })
       when not is_nil(ad) do
    length(String.split(ad, ",")) == 3
  end

  defp jormp_jomp?(_), do: false

  # Jormp jomp received: the attacker is the one who got jormp jomped.
  defp jormp_received_delta(%GameLogEvent{player: p, defender: d, log_seq: s} = event)
       when not is_nil(p) do
    if jormp_jomp?(event),
      do: [%{player: p, seq: s, delta: 1, event_type: "attacked", source_player: p, defender: d}],
      else: []
  end

  defp jormp_received_delta(_), do: []

  # Jormp jomp delivered: the defender is the one who delivered it.
  defp jormp_delivered_delta(%GameLogEvent{player: p, defender: d, log_seq: s} = event)
       when not is_nil(d) do
    if jormp_jomp?(event),
      do: [%{player: d, seq: s, delta: 1, event_type: "attacked", source_player: p, defender: d}],
      else: []
  end

  defp jormp_delivered_delta(_), do: []

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
