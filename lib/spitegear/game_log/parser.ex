defmodule Spitegear.GameLog.Parser do
  @moduledoc """
  Pure-function parser for wargear.net game log action strings.

  Each row in the log table is a map with these keys (all strings):
    :action  - the full action text from the Action column
    :ad      - attacker dice (e.g. "4,3,2"), empty for non-combat events
    :dd      - defender dice (e.g. "5,5")
    :bmod    - battle modifier (e.g. "-1,0")
    :al      - attacker losses
    :dl      - defender losses

  Returns {:ok, attrs_map} or {:unrecognized, raw_action_string}.

  For attacks/occupied, `attacker` is always the acting player.
  `defender` is extracted where the action string unambiguously names it
  (eliminated, captured_cards, captured_reserve_units). For attacks, the
  defender+from_territory are concatenated; territory_to is extracted but
  defender and territory_from require a second-pass via
  `Processor.fill_defenders/0` which uses known player names per game.
  """

  # --- Public API ---

  @spec parse_row(map()) :: {:ok, map()} | {:unrecognized, String.t()}
  def parse_row(%{action: action} = row) do
    cols = Map.take(row, [:ad, :dd, :bmod, :al, :dl])
    parse_core(action, cols) || {:unrecognized, action}
  end

  defp parse_core(action, cols) do
    parse_setup(action) ||
      parse_game_setup(action) ||
      parse_turn_lifecycle(action) ||
      parse_unit_receipt(action) ||
      parse_placement(action) ||
      parse_combat(action, cols) ||
      parse_movement(action) ||
      parse_cards(action) ||
      parse_game_end(action)
  end

  # --- Group parsers ---

  defp parse_setup("Initial board setup complete"), do: {:ok, %{event_type: "setup"}}
  defp parse_setup("Game started"), do: {:ok, %{event_type: "game_started"}}
  defp parse_setup("Game created"), do: {:ok, %{event_type: "game_created"}}
  defp parse_setup("Game joined"), do: {:ok, %{event_type: "game_joined"}}
  defp parse_setup("Game declined"), do: {:ok, %{event_type: "game_declined"}}
  defp parse_setup("Fogged"), do: {:ok, %{event_type: "fogged"}}

  # "Turn order set to 5,6,3,4,7,2,1" — system event (seat=0); raw_action preserves the order
  defp parse_setup(action) do
    if Regex.match?(~r/^Turn order set to [\d,]+$/, action),
      do: {:ok, %{event_type: "turn_order_set"}},
      else: nil
  end

  # Game setup events: factory/seat assignments and territory drafting
  defp parse_game_setup(action) do
    cond do
      # "Assigned Capital Castle Black +2 to dandodd"
      # "Assigned Capital Land 1.9 to Neutral"
      # Player may be "Neutral" for unowned capitals; \s+ handles occasional double-space
      m = match(~r/^Assigned Capital (?P<t>.+?)\s+to\s+(?P<p>.+)$/, action) ->
        player = if m["p"] == "Neutral", do: nil, else: m["p"]
        {:ok, %{event_type: "assigned_capital", territory_to: String.trim(m["t"]), player: player}}

      # "Assigned factory Nothgierc to pants off vant hof"
      m = match(~r/^Assigned factory (?P<t>.+?) to (?P<p>.+)$/, action) ->
        {:ok, %{event_type: "assigned_factory", territory_to: m["t"], player: m["p"]}}

      # "Assigned seat 1 to Kyjygyfyf"
      m = match(~r/^Assigned seat (?P<n>\d+) to (?P<p>.+)$/, action) ->
        {:ok, %{event_type: "assigned_seat", seat: to_int(m["n"]), player: m["p"]}}

      # "Hesh selected Brindlewood"
      m = match(~r/^(?P<p>.+?) selected (?P<t>.+)$/, action) ->
        {:ok, %{event_type: "selected_territory", player: m["p"], territory_to: m["t"]}}

      # "Hesh selected" (empty pick)
      m = match(~r/^(?P<p>.+?) selected$/, action) ->
        {:ok, %{event_type: "selected_territory", player: m["p"]}}

      true ->
        nil
    end
  end

  defp parse_turn_lifecycle(action) do
    cond do
      m = match(~r/^(?P<p>.+?) started turn$/, action) ->
        {:ok, %{event_type: "started_turn", player: m["p"]}}

      m = match(~r/^(?P<p>.+?) ended turn$/, action) ->
        {:ok, %{event_type: "ended_turn", player: m["p"]}}

      m = match(~r/^(?P<p>.+?) skipped turn$/, action) ->
        {:ok, %{event_type: "skipped_turn", player: m["p"]}}

      true ->
        nil
    end
  end

  defp parse_unit_receipt(action) do
    cond do
      # Note units? — wargear sometimes emits "bonus unit" (singular)
      m = match(~r/^(?P<p>.+?) received (?P<n>\d+) bonus units?$/, action) ->
        {:ok, %{event_type: "received_bonus", player: m["p"], units: to_int(m["n"])}}

      m = match(~r/^(?P<p>.+?) received (?P<n>\d+) units?$/, action) ->
        {:ok, %{event_type: "received_units", player: m["p"], units: to_int(m["n"])}}

      m = match(~r/^(?P<p>.+?) received elimination bonus of (?P<n>\d+) units?$/, action) ->
        {:ok, %{event_type: "received_elimination_bonus", player: m["p"], units: to_int(m["n"])}}

      true ->
        nil
    end
  end

  defp parse_placement(action) do
    cond do
      m = match(~r/^(?P<p>.+?) placed (?P<n>\d+) units? on (?P<t>.+)$/, action) ->
        {:ok,
         %{
           event_type: "placed_units",
           player: m["p"],
           units: to_int(m["n"]),
           territory_to: m["t"]
         }}

      # Edge case: "placed N units on" with no territory (empty in log)
      m = match(~r/^(?P<p>.+?) placed (?P<n>\d+) units? on$/, action) ->
        {:ok,
         %{event_type: "placed_units", player: m["p"], units: to_int(m["n"]), territory_to: nil}}

      # "factory produced N units on Territory +1" — trailing modifier stripped via lazy territory match
      m =
          match(
            ~r/^(?P<p>.+?) factory produced (?P<n>\d+) units? on (?P<t>.+?)(?:\s+[+-]\d+)?$/,
            action
          ) ->
        {:ok,
         %{
           event_type: "factory_produced",
           player: m["p"],
           units: to_int(m["n"]),
           territory_to: m["t"]
         }}

      m =
          match(
            ~r/^(?P<p>.+?) factory destroyed (?P<n>\d+) units? on (?P<t>.+?)(?:\s+[+-]\d+)?$/,
            action
          ) ->
        {:ok,
         %{
           event_type: "factory_destroyed",
           player: m["p"],
           units: to_int(m["n"]),
           territory_to: m["t"]
         }}

      # "Hesh captured Capital D Capital" — capital territory capture (no unit count)
      m = match(~r/^(?P<p>.+?) captured (?P<t>Capital .+)$/, action) ->
        {:ok, %{event_type: "captured_capital", player: m["p"], territory_to: m["t"]}}

      # "Kyjygyfyf conquered Capital p1" — same concept, different verb used in some map types
      m = match(~r/^(?P<p>.+?) conquered (?P<t>Capital .+)$/, action) ->
        {:ok, %{event_type: "conquered_capital", player: m["p"], territory_to: m["t"]}}

      # "Neutralised D1 with 1 unit" — system event (seat=0), territory neutralized on capital capture
      m = match(~r/^Neutralised (?P<t>.+?) with (?P<n>\d+) units?$/, action) ->
        {:ok, %{event_type: "neutralised", territory_to: m["t"], units: to_int(m["n"])}}

      true ->
        nil
    end
  end

  defp parse_combat(action, cols) do
    cond do
      # attacked with units/percentage format (no dice columns):
      # "Hesh attacked Kyjygyfyf Crumb > Easter Bunny with 8 units (65% vs 70%) AL1 / DL1"
      # losses are embedded in the action string rather than separate columns
      m =
          match(
            ~r/^(?P<p>.+?) attacked .+ > (?P<to>.+?) with (?P<n>\d+) units? \(\d+% vs \d+%\) AL(?P<al>\d+) \/ DL(?P<dl>\d+)$/,
            action
          ) ->
        {:ok,
         %{
           event_type: "attacked",
           player: m["p"],
           territory_to: m["to"],
           units: to_int(m["n"]),
           attacker_losses: to_int(m["al"]),
           defender_losses: to_int(m["dl"])
         }}

      # attacked: handles dice modifier variants:
      #   classic:  > Foo (5,3,3) (2,2)
      #   inter:    > Foo (4,2,1)-1 (4,2)
      #   pre+post: > Foo +0 (5,1) (1)+1
      m =
          match(
            ~r/^(?P<p>.+?) attacked .+ > (?P<to>.+?) (?:[+-]\d+ )?\([\d,]+\)(?:[+-]\d+)? \([\d,]+\)(?:[+-]\d+)?$/,
            action
          ) ->
        {:ok,
         %{
           event_type: "attacked",
           player: m["p"],
           territory_to: m["to"],
           attacker_dice: nil_blank(cols[:ad]),
           defender_dice: nil_blank(cols[:dd]),
           battle_mod: nil_blank(cols[:bmod]),
           attacker_losses: to_int(cols[:al]),
           defender_losses: to_int(cols[:dl])
         }}

      m = match(~r/^(?P<p>.+?) occupied .+ > (?P<to>.+?) with (?P<n>\d+) units?$/, action) ->
        {:ok,
         %{event_type: "occupied", player: m["p"], territory_to: m["to"], units: to_int(m["n"])}}

      # attacked: no territory_to — dice immediately follow ">"
      # "pants off vant hof attacked Hesh Burkina Faso >  (5,5,3) (6,2)"
      # Note: Floki may produce double whitespace after ">" when territory cell is empty
      m =
          match(
            ~r/^(?P<p>.+?) attacked .+>\s+(?:[+-]\d+ )?\([\d,]+\)(?:[+-]\d+)? \([\d,]+\)(?:[+-]\d+)?$/,
            action
          ) ->
        {:ok,
         %{
           event_type: "attacked",
           player: m["p"],
           territory_to: nil,
           attacker_dice: nil_blank(cols[:ad]),
           defender_dice: nil_blank(cols[:dd]),
           battle_mod: nil_blank(cols[:bmod]),
           attacker_losses: to_int(cols[:al]),
           defender_losses: to_int(cols[:dl])
         }}

      # occupied: no territory_to — "pants off vant hof occupied Hesh Burkina Faso >  with 2 units"
      # Note: Floki may produce double whitespace after ">" when territory cell is empty
      m = match(~r/^(?P<p>.+?) occupied .+>\s+with (?P<n>\d+) units?$/, action) ->
        {:ok, %{event_type: "occupied", player: m["p"], territory_to: nil, units: to_int(m["n"])}}

      true ->
        nil
    end
  end

  defp parse_movement(action) do
    cond do
      m = match(~r/^(?P<p>.+?) fortified (?P<n>\d+) units? (?P<from>.+) > (?P<to>.+)$/, action) ->
        {:ok,
         %{
           event_type: "fortified",
           player: m["p"],
           units: to_int(m["n"]),
           territory_from: m["from"],
           territory_to: m["to"]
         }}

      # Edge case: "fortified N units Territory >" with empty destination
      m = match(~r/^(?P<p>.+?) fortified (?P<n>\d+) units? (?P<from>.+) >$/, action) ->
        {:ok,
         %{
           event_type: "fortified",
           player: m["p"],
           units: to_int(m["n"]),
           territory_from: m["from"]
         }}

      m = match(~r/^(?P<p>.+?) transferred (?P<n>\d+) units? (?P<from>.+) > (?P<to>.+)$/, action) ->
        {:ok,
         %{
           event_type: "transferred",
           player: m["p"],
           units: to_int(m["n"]),
           territory_from: m["from"],
           territory_to: m["to"]
         }}

      # "transferred N units > Guinea" — only destination, no source territory
      # Note: Floki may produce double whitespace before ">" when source territory cell is empty
      m = match(~r/^(?P<p>.+?) transferred (?P<n>\d+) units?\s+>\s+(?P<to>.+)$/, action) ->
        {:ok,
         %{
           event_type: "transferred",
           player: m["p"],
           units: to_int(m["n"]),
           territory_to: m["to"]
         }}

      # "transferred N units Guinea >" — only source, no destination territory
      m = match(~r/^(?P<p>.+?) transferred (?P<n>\d+) units? (?P<from>.+) >$/, action) ->
        {:ok,
         %{
           event_type: "transferred",
           player: m["p"],
           units: to_int(m["n"]),
           territory_from: m["from"]
         }}

      # "Hesh reinforced 10 units Chef > Dragonfruit" — same semantics as transferred/fortified
      m = match(~r/^(?P<p>.+?) reinforced (?P<n>\d+) units? (?P<from>.+) > (?P<to>.+)$/, action) ->
        {:ok,
         %{
           event_type: "reinforced",
           player: m["p"],
           units: to_int(m["n"]),
           territory_from: m["from"],
           territory_to: m["to"]
         }}

      # "Hesh assimilated 3 units from C4" — absorbs units from a captured territory
      m = match(~r/^(?P<p>.+?) assimilated (?P<n>\d+) units? from (?P<t>.+)$/, action) ->
        {:ok,
         %{
           event_type: "assimilated",
           player: m["p"],
           units: to_int(m["n"]),
           territory_from: m["t"]
         }}

      true ->
        nil
    end
  end

  defp parse_cards(action) do
    cond do
      m = match(~r/^(?P<p>.+?) awarded card$/, action) ->
        {:ok, %{event_type: "awarded_card", player: m["p"]}}

      # "traded cards (CCC) for 4 units" — capture unit count
      m = match(~r/^(?P<p>.+?) traded cards? .+ for (?P<n>\d+) units?$/, action) ->
        {:ok, %{event_type: "traded_cards", player: m["p"], units: to_int(m["n"])}}

      # traded cards without a unit count in the action string
      m = match(~r/^(?P<p>.+?) traded cards?/, action) ->
        {:ok, %{event_type: "traded_cards", player: m["p"]}}

      m = match(~r/^(?P<p>.+?) captured (?P<n>\d+) cards? from (?P<d>.+)$/, action) ->
        {:ok,
         %{
           event_type: "captured_cards",
           player: m["p"],
           units: to_int(m["n"]),
           defender: m["d"]
         }}

      # "dandodd captured 3 reserve units from Kyjygyfyf"
      m = match(~r/^(?P<p>.+?) captured (?P<n>\d+) reserve units? from (?P<d>.+)$/, action) ->
        {:ok,
         %{
           event_type: "captured_reserve_units",
           player: m["p"],
           units: to_int(m["n"]),
           defender: m["d"]
         }}

      # "Hesh discarded 7 units"
      m = match(~r/^(?P<p>.+?) discarded (?P<n>\d+) units?$/, action) ->
        {:ok, %{event_type: "discarded_units", player: m["p"], units: to_int(m["n"])}}

      true ->
        nil
    end
  end

  defp parse_game_end(action) do
    cond do
      m = match(~r/^(?P<p>.+?) eliminated (?P<d>.+)$/, action) ->
        {:ok, %{event_type: "eliminated", player: m["p"], defender: m["d"]}}

      m = match(~r/^Game won by (?P<p>.+)$/, action) ->
        {:ok, %{event_type: "game_won", player: m["p"]}}

      m = match(~r/^(?P<p>.+?) won$/, action) ->
        {:ok, %{event_type: "game_won", player: m["p"]}}

      m = match(~r/^(?P<p>.+?) surrendered$/, action) ->
        {:ok, %{event_type: "surrendered", player: m["p"]}}

      m = match(~r/^(?P<p>.+?) timed out$/, action) ->
        {:ok, %{event_type: "timed_out", player: m["p"]}}

      true ->
        nil
    end
  end

  # --- Helpers ---

  defp match(regex, string) do
    Regex.named_captures(regex, string)
  end

  defp to_int(nil), do: nil
  defp to_int(""), do: nil

  defp to_int(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp nil_blank(nil), do: nil
  defp nil_blank(""), do: nil
  defp nil_blank(s), do: s
end
