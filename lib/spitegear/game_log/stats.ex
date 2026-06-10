defmodule Spitegear.GameLog.Stats do
  @moduledoc """
  Aggregate stats computed over processed GameLogEvent records.

  Functions here are pure reducers over event streams — no side effects.
  Each stat function fetches events for a game and folds over them.
  """

  import Ecto.Query

  require Logger

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

  # Precomputed expected losses for every (na, nd, battle_mod) combination
  # observed in the log history. Key: {attacker_dice, defender_dice, battle_mod}.
  # Values computed by full dice-outcome enumeration. Attacker wins each
  # comparison strictly; ties go to the defender.
  @expected_losses %{
    # --- 1 attacker die, 1 defender die ---
    {1, 1, "0,0"} => %{attacker: 0.583, defender: 0.417},
    {1, 1, "0,-1"} => %{attacker: 0.5, defender: 0.5},
    {1, 1, "0,1"} => %{attacker: 0.643, defender: 0.357},
    {1, 1, "0,-2"} => %{attacker: 0.417, defender: 0.583},
    {1, 1, "0,2"} => %{attacker: 0.688, defender: 0.313},
    {1, 1, "0,3"} => %{attacker: 0.722, defender: 0.278},
    {1, 1, "0,4"} => %{attacker: 0.75, defender: 0.25},
    {1, 1, "-1,0"} => %{attacker: 0.667, defender: 0.333},
    {1, 1, "1,0"} => %{attacker: 0.5, defender: 0.5},
    {1, 1, "-1,-1"} => %{attacker: 0.6, defender: 0.4},
    {1, 1, "-1,1"} => %{attacker: 0.714, defender: 0.286},
    {1, 1, "1,-1"} => %{attacker: 0.429, defender: 0.571},
    {1, 1, "1,1"} => %{attacker: 0.571, defender: 0.429},
    {1, 1, "-1,2"} => %{attacker: 0.75, defender: 0.25},
    {1, 1, "1,-2"} => %{attacker: 0.357, defender: 0.643},
    {1, 1, "1,2"} => %{attacker: 0.625, defender: 0.375},
    {1, 1, "-1,3"} => %{attacker: 0.778, defender: 0.222},
    {1, 1, "1,3"} => %{attacker: 0.667, defender: 0.333},
    {1, 1, "1,4"} => %{attacker: 0.7, defender: 0.3},
    {1, 1, "-2,0"} => %{attacker: 0.75, defender: 0.25},
    {1, 1, "2,0"} => %{attacker: 0.438, defender: 0.563},
    {1, 1, "-2,1"} => %{attacker: 0.786, defender: 0.214},
    {1, 1, "2,-1"} => %{attacker: 0.375, defender: 0.625},
    {1, 1, "2,1"} => %{attacker: 0.5, defender: 0.5},
    {1, 1, "2,2"} => %{attacker: 0.563, defender: 0.438},
    {1, 1, "2,3"} => %{attacker: 0.611, defender: 0.389},
    {1, 1, "2,4"} => %{attacker: 0.65, defender: 0.35},
    {1, 1, "3,0"} => %{attacker: 0.389, defender: 0.611},
    {1, 1, "3,2"} => %{attacker: 0.5, defender: 0.5},
    {1, 1, "3,6"} => %{attacker: 0.667, defender: 0.333},
    {1, 1, "4,0"} => %{attacker: 0.35, defender: 0.65},
    # --- 1 attacker die, 2 defender dice ---
    {1, 2, "0,0"} => %{attacker: 0.745, defender: 0.255},
    {1, 2, "0,-1"} => %{attacker: 0.633, defender: 0.367},
    {1, 2, "0,1"} => %{attacker: 0.813, defender: 0.187},
    {1, 2, "0,-2"} => %{attacker: 0.521, defender: 0.479},
    {1, 2, "0,2"} => %{attacker: 0.857, defender: 0.143},
    {1, 2, "0,3"} => %{attacker: 0.887, defender: 0.113},
    {1, 2, "0,4"} => %{attacker: 0.908, defender: 0.092},
    {1, 2, "-1,0"} => %{attacker: 0.833, defender: 0.167},
    {1, 2, "1,0"} => %{attacker: 0.639, defender: 0.361},
    {1, 2, "-1,-1"} => %{attacker: 0.76, defender: 0.24},
    {1, 2, "-1,1"} => %{attacker: 0.878, defender: 0.122},
    {1, 2, "1,-1"} => %{attacker: 0.543, defender: 0.457},
    {1, 2, "1,1"} => %{attacker: 0.735, defender: 0.265},
    {1, 2, "-1,2"} => %{attacker: 0.906, defender: 0.094},
    {1, 2, "1,-2"} => %{attacker: 0.446, defender: 0.554},
    {1, 2, "1,2"} => %{attacker: 0.797, defender: 0.203},
    {1, 2, "-1,3"} => %{attacker: 0.926, defender: 0.074},
    {1, 2, "1,3"} => %{attacker: 0.84, defender: 0.16},
    {1, 2, "1,4"} => %{attacker: 0.87, defender: 0.13},
    {1, 2, "-2,0"} => %{attacker: 0.903, defender: 0.097},
    {1, 2, "2,0"} => %{attacker: 0.559, defender: 0.441},
    {1, 2, "-2,1"} => %{attacker: 0.929, defender: 0.071},
    {1, 2, "2,-1"} => %{attacker: 0.475, defender: 0.525},
    {1, 2, "2,1"} => %{attacker: 0.643, defender: 0.357},
    {1, 2, "2,2"} => %{attacker: 0.727, defender: 0.273},
    {1, 2, "2,3"} => %{attacker: 0.784, defender: 0.216},
    {1, 2, "2,4"} => %{attacker: 0.825, defender: 0.175},
    {1, 2, "3,0"} => %{attacker: 0.497, defender: 0.503},
    {1, 2, "3,2"} => %{attacker: 0.646, defender: 0.354},
    {1, 2, "3,6"} => %{attacker: 0.843, defender: 0.157},
    {1, 2, "4,0"} => %{attacker: 0.447, defender: 0.553},
    # --- 2 attacker dice, 1 defender die ---
    {2, 1, "0,0"} => %{attacker: 0.421, defender: 0.579},
    {2, 1, "0,-1"} => %{attacker: 0.306, defender: 0.694},
    {2, 1, "0,1"} => %{attacker: 0.504, defender: 0.496},
    {2, 1, "0,-2"} => %{attacker: 0.208, defender: 0.792},
    {2, 1, "0,2"} => %{attacker: 0.566, defender: 0.434},
    {2, 1, "0,3"} => %{attacker: 0.614, defender: 0.386},
    {2, 1, "0,4"} => %{attacker: 0.653, defender: 0.347},
    {2, 1, "-1,0"} => %{attacker: 0.533, defender: 0.467},
    {2, 1, "1,0"} => %{attacker: 0.31, defender: 0.69},
    {2, 1, "-1,-1"} => %{attacker: 0.44, defender: 0.56},
    {2, 1, "-1,1"} => %{attacker: 0.6, defender: 0.4},
    {2, 1, "1,-1"} => %{attacker: 0.224, defender: 0.776},
    {2, 1, "1,1"} => %{attacker: 0.408, defender: 0.592},
    {2, 1, "-1,2"} => %{attacker: 0.65, defender: 0.35},
    {2, 1, "1,-2"} => %{attacker: 0.153, defender: 0.847},
    {2, 1, "1,2"} => %{attacker: 0.482, defender: 0.518},
    {2, 1, "-1,3"} => %{attacker: 0.689, defender: 0.311},
    {2, 1, "1,3"} => %{attacker: 0.54, defender: 0.46},
    {2, 1, "1,4"} => %{attacker: 0.586, defender: 0.414},
    {2, 1, "-2,0"} => %{attacker: 0.646, defender: 0.354},
    {2, 1, "2,0"} => %{attacker: 0.237, defender: 0.763},
    {2, 1, "-2,1"} => %{attacker: 0.696, defender: 0.304},
    {2, 1, "2,-1"} => %{attacker: 0.172, defender: 0.828},
    {2, 1, "2,1"} => %{attacker: 0.313, defender: 0.688},
    {2, 1, "2,2"} => %{attacker: 0.398, defender: 0.602},
    {2, 1, "2,3"} => %{attacker: 0.465, defender: 0.535},
    {2, 1, "2,4"} => %{attacker: 0.519, defender: 0.481},
    {2, 1, "3,0"} => %{attacker: 0.187, defender: 0.813},
    {2, 1, "3,2"} => %{attacker: 0.315, defender: 0.685},
    {2, 1, "3,6"} => %{attacker: 0.543, defender: 0.457},
    {2, 1, "4,0"} => %{attacker: 0.152, defender: 0.848},
    # --- 2 attacker dice, 2 defender dice ---
    {2, 2, "0,0"} => %{attacker: 1.221, defender: 0.779},
    {2, 2, "0,-1"} => %{attacker: 1.0, defender: 1.0},
    {2, 2, "0,1"} => %{attacker: 1.365, defender: 0.635},
    {2, 2, "0,-2"} => %{attacker: 0.799, defender: 1.201},
    {2, 2, "0,2"} => %{attacker: 1.466, defender: 0.534},
    {2, 2, "0,3"} => %{attacker: 1.54, defender: 0.46},
    {2, 2, "0,4"} => %{attacker: 1.597, defender: 0.403},
    {2, 2, "-1,0"} => %{attacker: 1.422, defender: 0.578},
    {2, 2, "1,0"} => %{attacker: 1.0, defender: 1.0},
    {2, 2, "-1,-1"} => %{attacker: 1.264, defender: 0.736},
    {2, 2, "-1,1"} => %{attacker: 1.527, defender: 0.473},
    {2, 2, "1,-1"} => %{attacker: 0.824, defender: 1.176},
    {2, 2, "1,1"} => %{attacker: 1.19, defender: 0.81},
    {2, 2, "-1,2"} => %{attacker: 1.6, defender: 0.4},
    {2, 2, "1,-2"} => %{attacker: 0.663, defender: 1.337},
    {2, 2, "1,2"} => %{attacker: 1.321, defender: 0.679},
    {2, 2, "-1,3"} => %{attacker: 1.654, defender: 0.346},
    {2, 2, "1,3"} => %{attacker: 1.418, defender: 0.582},
    {2, 2, "1,4"} => %{attacker: 1.491, defender: 0.509},
    {2, 2, "-2,0"} => %{attacker: 1.604, defender: 0.396},
    {2, 2, "2,0"} => %{attacker: 0.845, defender: 1.155},
    {2, 2, "-2,1"} => %{attacker: 1.673, defender: 0.327},
    {2, 2, "2,-1"} => %{attacker: 0.7, defender: 1.3},
    {2, 2, "2,1"} => %{attacker: 1.0, defender: 1.0},
    {2, 2, "2,2"} => %{attacker: 1.166, defender: 0.834},
    {2, 2, "2,3"} => %{attacker: 1.287, defender: 0.713},
    {2, 2, "2,4"} => %{attacker: 1.379, defender: 0.621},
    {2, 2, "3,0"} => %{attacker: 0.73, defender: 1.27},
    {2, 2, "3,2"} => %{attacker: 1.0, defender: 1.0},
    {2, 2, "3,6"} => %{attacker: 1.416, defender: 0.584},
    {2, 2, "4,0"} => %{attacker: 0.642, defender: 1.358},
    # --- 3 attacker dice, 1 defender die ---
    {3, 1, "0,0"} => %{attacker: 0.34, defender: 0.66},
    {3, 1, "0,-1"} => %{attacker: 0.208, defender: 0.792},
    {3, 1, "0,1"} => %{attacker: 0.435, defender: 0.565},
    {3, 1, "0,-2"} => %{attacker: 0.116, defender: 0.884},
    {3, 1, "0,2"} => %{attacker: 0.505, defender: 0.495},
    {3, 1, "0,3"} => %{attacker: 0.56, defender: 0.44},
    {3, 1, "0,4"} => %{attacker: 0.604, defender: 0.396},
    {3, 1, "-1,0"} => %{attacker: 0.467, defender: 0.533},
    {3, 1, "1,0"} => %{attacker: 0.214, defender: 0.786},
    {3, 1, "-1,-1"} => %{attacker: 0.36, defender: 0.64},
    {3, 1, "-1,1"} => %{attacker: 0.543, defender: 0.457},
    {3, 1, "1,-1"} => %{attacker: 0.131, defender: 0.869},
    {3, 1, "1,1"} => %{attacker: 0.327, defender: 0.673},
    {3, 1, "-1,2"} => %{attacker: 0.6, defender: 0.4},
    {3, 1, "1,-2"} => %{attacker: 0.073, defender: 0.927},
    {3, 1, "1,2"} => %{attacker: 0.411, defender: 0.589},
    {3, 1, "-1,3"} => %{attacker: 0.644, defender: 0.356},
    {3, 1, "1,3"} => %{attacker: 0.476, defender: 0.524},
    {3, 1, "1,4"} => %{attacker: 0.529, defender: 0.471},
    {3, 1, "-2,0"} => %{attacker: 0.594, defender: 0.406},
    {3, 1, "2,0"} => %{attacker: 0.144, defender: 0.856},
    {3, 1, "-2,1"} => %{attacker: 0.652, defender: 0.348},
    {3, 1, "2,-1"} => %{attacker: 0.088, defender: 0.912},
    {3, 1, "2,1"} => %{attacker: 0.219, defender: 0.781},
    {3, 1, "2,2"} => %{attacker: 0.316, defender: 0.684},
    {3, 1, "2,3"} => %{attacker: 0.392, defender: 0.608},
    {3, 1, "2,4"} => %{attacker: 0.453, defender: 0.547},
    {3, 1, "3,0"} => %{attacker: 0.101, defender: 0.899},
    {3, 1, "3,2"} => %{attacker: 0.222, defender: 0.778},
    {3, 1, "3,6"} => %{attacker: 0.481, defender: 0.519},
    {3, 1, "4,0"} => %{attacker: 0.073, defender: 0.926},
    # --- 3 attacker dice, 2 defender dice ---
    {3, 2, "0,0"} => %{attacker: 0.921, defender: 1.079},
    {3, 2, "0,-1"} => %{attacker: 0.646, defender: 1.354},
    {3, 2, "0,1"} => %{attacker: 1.105, defender: 0.895},
    {3, 2, "0,-2"} => %{attacker: 0.429, defender: 1.571},
    {3, 2, "0,2"} => %{attacker: 1.237, defender: 0.763},
    {3, 2, "0,3"} => %{attacker: 1.335, defender: 0.665},
    {3, 2, "0,4"} => %{attacker: 1.412, defender: 0.588},
    {3, 2, "-1,0"} => %{attacker: 1.172, defender: 0.828},
    {3, 2, "1,0"} => %{attacker: 0.653, defender: 1.347},
    {3, 2, "-1,-1"} => %{attacker: 0.968, defender: 1.032},
    {3, 2, "-1,1"} => %{attacker: 1.31, defender: 0.69},
    {3, 2, "1,-1"} => %{attacker: 0.461, defender: 1.539},
    {3, 2, "1,1"} => %{attacker: 0.888, defender: 1.112},
    {3, 2, "-1,2"} => %{attacker: 1.409, defender: 0.591},
    {3, 2, "1,-2"} => %{attacker: 0.309, defender: 1.691},
    {3, 2, "1,2"} => %{attacker: 1.055, defender: 0.945},
    {3, 2, "-1,3"} => %{attacker: 1.484, defender: 0.516},
    {3, 2, "1,3"} => %{attacker: 1.179, defender: 0.821},
    {3, 2, "1,4"} => %{attacker: 1.275, defender: 0.725},
    {3, 2, "-2,0"} => %{attacker: 1.406, defender: 0.594},
    {3, 2, "2,0"} => %{attacker: 0.486, defender: 1.514},
    {3, 2, "-2,1"} => %{attacker: 1.503, defender: 0.497},
    {3, 2, "2,-1"} => %{attacker: 0.345, defender: 1.655},
    {3, 2, "2,1"} => %{attacker: 0.658, defender: 1.342},
    {3, 2, "2,2"} => %{attacker: 0.864, defender: 1.136},
    {3, 2, "2,3"} => %{attacker: 1.016, defender: 0.984},
    {3, 2, "2,4"} => %{attacker: 1.133, defender: 0.867},
    {3, 2, "3,0"} => %{attacker: 0.376, defender: 1.624},
    {3, 2, "3,2"} => %{attacker: 0.663, defender: 1.337},
    {3, 2, "3,6"} => %{attacker: 1.183, defender: 0.817},
    {3, 2, "4,0"} => %{attacker: 0.299, defender: 1.701}
  }

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
  Returns a single-series map `%{"Total" => points}` tracking the total number
  of units on the board over time.

  Board gains: setup placements (aggregated at the cutoff seq), then all
  positive unit events (bonuses, factory production, card trades, etc.).
  Board losses: attacker + defender losses per attack combined into one point,
  plus factory_destroyed and discarded_units. `captured_reserve_units` is a
  player-to-player transfer — no net board change.
  """
  def total_board_units_series(game_id) do
    events =
      Repo.all(
        from(e in GameLogEvent,
          where: e.game_id == ^game_id,
          order_by: [asc: e.log_seq]
        )
      )

    cutoff = setup_cutoff(events)

    setup_entry =
      if cutoff > 0 do
        total =
          events
          |> Enum.take_while(&(&1.log_seq < cutoff))
          |> Enum.flat_map(&setup_placed_delta/1)
          |> Enum.map(& &1.delta)
          |> Enum.sum()

        if total > 0,
          do: [
            %{
              player: "Total",
              seq: cutoff,
              delta: total,
              event_type: "setup",
              source_player: nil,
              defender: nil
            }
          ],
          else: []
      else
        []
      end

    game_deltas =
      events
      |> Enum.drop_while(&(&1.log_seq < cutoff))
      |> Enum.flat_map(&board_total_delta/1)

    (setup_entry ++ game_deltas)
    |> build_series()
  end

  @doc """
  Returns the expected losses for each side in a single `"attacked"` event,
  accounting for the number of dice rolled and the battle modifier.

  `battle_mod` is parsed as `"attacker_mod,defender_mod"` — each modifier shifts
  the die size from the default 6 by that amount (e.g. `"0,1"` gives the
  defender a 7-sided die; `"-1,0"` gives the attacker a 5-sided die). Ties in
  each comparison go to the defender.

  Returns `%{attacker: float, defender: float}` rounded to three decimal places,
  or `nil` for non-attack events or events missing dice fields.
  """
  @spec expected_attack_losses(GameLogEvent.t()) ::
          %{attacker: float(), defender: float()} | nil
  def expected_attack_losses(%GameLogEvent{
        event_type: "attacked",
        attacker_dice: ad,
        defender_dice: dd,
        battle_mod: bm
      })
      when not is_nil(ad) and not is_nil(dd) do
    na = ad |> String.split(",") |> length()
    nd = dd |> String.split(",") |> length()
    key = {na, nd, bm || "0,0"}

    case Map.fetch(@expected_losses, key) do
      {:ok, result} ->
        result

      :error ->
        Logger.error("#{__MODULE__} unknown battle config #{inspect(key)} — computing on the fly")
        {a_mod, d_mod} = parse_battle_mod(bm)
        compute_expected_losses(na, nd, 6 + a_mod, 6 + d_mod)
    end
  end

  def expected_attack_losses(_), do: nil

  @doc """
  Returns the luck delta for each side of a single `"attacked"` event:
  `expected_losses - actual_losses`. Positive means the side lost fewer
  units than the dice odds predict (lucky); negative means unlucky.

  Returns `%{attacker: float, defender: float}` or `nil` if the event is
  not an attack or is missing required fields.
  """
  @spec attack_luck_delta(GameLogEvent.t()) :: %{attacker: float(), defender: float()} | nil
  def attack_luck_delta(
        %GameLogEvent{event_type: "attacked", attacker_losses: al, defender_losses: dl} = event
      )
      when not is_nil(al) and not is_nil(dl) do
    case expected_attack_losses(event) do
      nil ->
        nil

      %{attacker: exp_al, defender: exp_dl} ->
        %{attacker: Float.round(exp_al - al, 3), defender: Float.round(exp_dl - dl, 3)}
    end
  end

  def attack_luck_delta(_), do: nil

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
  Returns a per-player cumulative luck series, keyed by player name.
  Same point shape as `enriched_net_units_series/1`.

  For each attack, both the attacker and defender receive a delta of
  `expected_losses - actual_losses`. A positive cumulative value means the
  player has been lucky (lost fewer units than the dice odds predict);
  negative means unlucky. The running total is a troop-equivalent measure
  of luck across the entire game.
  """
  def luck_delta_series(game_id) do
    Repo.all(
      from(e in GameLogEvent,
        where: e.game_id == ^game_id,
        order_by: [asc: e.log_seq]
      )
    )
    |> Enum.flat_map(&luck_event_deltas/1)
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

  # Board total: positive events add to the whole board's unit count.
  defp board_total_delta(%GameLogEvent{event_type: t, player: p, units: u, log_seq: s})
       when t in @positive_unit_events and not is_nil(u) do
    [%{player: "Total", seq: s, delta: u, event_type: t, source_player: p, defender: nil}]
  end

  # Board total: attacker + defender losses both leave the board; combine into one point.
  defp board_total_delta(%GameLogEvent{
         event_type: "attacked",
         player: p,
         defender: d,
         attacker_losses: al,
         defender_losses: dl,
         log_seq: s
       }) do
    loss = (al || 0) + (dl || 0)

    if loss > 0,
      do: [
        %{
          player: "Total",
          seq: s,
          delta: -loss,
          event_type: "attacked",
          source_player: p,
          defender: d
        }
      ],
      else: []
  end

  defp board_total_delta(%GameLogEvent{
         event_type: "factory_destroyed",
         player: p,
         units: u,
         log_seq: s
       })
       when not is_nil(u) do
    [
      %{
        player: "Total",
        seq: s,
        delta: -u,
        event_type: "factory_destroyed",
        source_player: p,
        defender: nil
      }
    ]
  end

  defp board_total_delta(%GameLogEvent{
         event_type: "discarded_units",
         player: p,
         units: u,
         log_seq: s
       })
       when not is_nil(u) do
    [
      %{
        player: "Total",
        seq: s,
        delta: -u,
        event_type: "discarded_units",
        source_player: p,
        defender: nil
      }
    ]
  end

  defp board_total_delta(_), do: []

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

  # Expected-vs-actual luck deltas for both sides of an attack (for luck_delta_series).
  defp luck_event_deltas(
         %GameLogEvent{
           event_type: "attacked",
           player: attacker,
           defender: defender,
           attacker_losses: al,
           defender_losses: dl,
           log_seq: s
         } = event
       )
       when not is_nil(attacker) and not is_nil(defender) and not is_nil(al) and not is_nil(dl) do
    case attack_luck_delta(event) do
      nil ->
        []

      %{attacker: a_luck, defender: d_luck} ->
        [
          %{
            player: attacker,
            seq: s,
            delta: a_luck,
            event_type: "attacked",
            source_player: attacker,
            defender: defender
          },
          %{
            player: defender,
            seq: s,
            delta: d_luck,
            event_type: "attacked",
            source_player: attacker,
            defender: defender
          }
        ]
    end
  end

  defp luck_event_deltas(_), do: []

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

  defp parse_battle_mod(nil), do: {0, 0}

  defp parse_battle_mod(bm) do
    [a, d] = bm |> String.split(",") |> Enum.map(&String.to_integer/1)
    {a, d}
  end

  # Enumerate all ordered n-tuples of rolls for a `size`-sided die.
  # Each tuple has equal probability, so averaging over all tuples gives
  # the exact expected value without needing weighted sampling.
  defp dice_outcomes(n, size) do
    Enum.reduce(1..n, [[]], fn _, acc ->
      for v <- 1..size, rest <- acc, do: [v | rest]
    end)
  end

  defp compute_expected_losses(na, nd, a_size, d_size) do
    pairs = min(na, nd)
    a_rolls = dice_outcomes(na, a_size)
    d_rolls = dice_outcomes(nd, d_size)
    total = length(a_rolls) * length(d_rolls)

    {al_sum, dl_sum} =
      for a <- a_rolls, d <- d_rolls, reduce: {0, 0} do
        {al, dl} ->
          {a_loss, d_loss} =
            battle_losses(Enum.sort(a, :desc), Enum.sort(d, :desc), pairs)

          {al + a_loss, dl + d_loss}
      end

    %{attacker: Float.round(al_sum / total, 3), defender: Float.round(dl_sum / total, 3)}
  end

  # Compare top `pairs` dice from each side. Attacker wins strictly; ties to defender.
  defp battle_losses(a_sorted, d_sorted, pairs) do
    Enum.zip(Enum.take(a_sorted, pairs), Enum.take(d_sorted, pairs))
    |> Enum.reduce({0, 0}, fn {a, d}, {al, dl} ->
      if a > d, do: {al, dl + 1}, else: {al + 1, dl}
    end)
  end

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
