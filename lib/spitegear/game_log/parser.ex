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
  `defender` is extracted only where the action string unambiguously
  separates it (eliminated). For attacks, the defender+from_territory
  are concatenated in the action text; territory_to is extracted but
  territory_from and defender are left nil for a future reprocess pass.
  """

  # --- Public API ---

  @spec parse_row(map()) :: {:ok, map()} | {:unrecognized, String.t()}
  def parse_row(%{action: action} = row) do
    cols = Map.take(row, [:ad, :dd, :bmod, :al, :dl])

    parse_setup(action) ||
      parse_turn_lifecycle(action) ||
      parse_unit_receipt(action) ||
      parse_placement(action) ||
      parse_combat(action, cols) ||
      parse_movement(action) ||
      parse_cards(action) ||
      parse_game_end(action) ||
      {:unrecognized, action}
  end

  # --- Group parsers ---

  defp parse_setup("Initial board setup complete"), do: {:ok, %{event_type: "setup"}}
  defp parse_setup(_), do: nil

  defp parse_turn_lifecycle(action) do
    cond do
      m = match(~r/^(?P<p>.+?) started turn$/, action) ->
        {:ok, %{event_type: "started_turn", attacker: m["p"]}}

      m = match(~r/^(?P<p>.+?) ended turn$/, action) ->
        {:ok, %{event_type: "ended_turn", attacker: m["p"]}}

      true ->
        nil
    end
  end

  defp parse_unit_receipt(action) do
    cond do
      m = match(~r/^(?P<p>.+?) received (?P<n>\d+) bonus units$/, action) ->
        {:ok, %{event_type: "received_bonus", attacker: m["p"], units: to_int(m["n"])}}

      m = match(~r/^(?P<p>.+?) received (?P<n>\d+) units?$/, action) ->
        {:ok, %{event_type: "received_units", attacker: m["p"], units: to_int(m["n"])}}

      true ->
        nil
    end
  end

  defp parse_placement(action) do
    cond do
      m = match(~r/^(?P<p>.+?) placed (?P<n>\d+) units? on (?P<t>.+)$/, action) ->
        {:ok, %{event_type: "placed_units", attacker: m["p"], units: to_int(m["n"]), territory_to: m["t"]}}

      # "factory produced N units on Territory +1" — trailing modifier stripped via lazy territory match
      m = match(~r/^(?P<p>.+?) factory produced (?P<n>\d+) units? on (?P<t>.+?)(?:\s+[+-]\d+)?$/, action) ->
        {:ok, %{event_type: "factory_produced", attacker: m["p"], units: to_int(m["n"]), territory_to: m["t"]}}

      true ->
        nil
    end
  end

  defp parse_combat(action, cols) do
    cond do
      # attacked: handles modifier variants:
      #   classic:  > Foo (5,3,3) (2,2)
      #   inter:    > Foo (4,2,1)-1 (4,2)
      #   pre+post: > Foo +0 (5,1) (1)+1
      m = match(~r/^(?P<p>.+?) attacked .+ > (?P<to>.+?) (?:[+-]\d+ )?\([\d,]+\)(?:[+-]\d+)? \([\d,]+\)(?:[+-]\d+)?$/, action) ->
        {:ok,
         %{
           event_type: "attacked",
           attacker: m["p"],
           territory_to: m["to"],
           attacker_dice: nil_blank(cols[:ad]),
           defender_dice: nil_blank(cols[:dd]),
           battle_mod: nil_blank(cols[:bmod]),
           attacker_losses: to_int(cols[:al]),
           defender_losses: to_int(cols[:dl])
         }}

      m = match(~r/^(?P<p>.+?) occupied .+ > (?P<to>.+?) with (?P<n>\d+) units?$/, action) ->
        {:ok, %{event_type: "occupied", attacker: m["p"], territory_to: m["to"], units: to_int(m["n"])}}

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
           attacker: m["p"],
           units: to_int(m["n"]),
           territory_from: m["from"],
           territory_to: m["to"]
         }}

      m = match(~r/^(?P<p>.+?) transferred (?P<n>\d+) units? (?P<from>.+) > (?P<to>.+)$/, action) ->
        {:ok,
         %{
           event_type: "transferred",
           attacker: m["p"],
           units: to_int(m["n"]),
           territory_from: m["from"],
           territory_to: m["to"]
         }}

      true ->
        nil
    end
  end

  defp parse_cards(action) do
    cond do
      m = match(~r/^(?P<p>.+?) awarded card$/, action) ->
        {:ok, %{event_type: "awarded_card", attacker: m["p"]}}

      # "traded cards (CCC) for 4 units" — capture unit count
      m = match(~r/^(?P<p>.+?) traded cards? .+ for (?P<n>\d+) units?$/, action) ->
        {:ok, %{event_type: "traded_cards", attacker: m["p"], units: to_int(m["n"])}}

      # traded cards without a unit count in the action string
      m = match(~r/^(?P<p>.+?) traded cards?/, action) ->
        {:ok, %{event_type: "traded_cards", attacker: m["p"]}}

      true ->
        nil
    end
  end

  defp parse_game_end(action) do
    cond do
      m = match(~r/^(?P<p>.+?) eliminated (?P<d>.+)$/, action) ->
        {:ok, %{event_type: "eliminated", attacker: m["p"], defender: m["d"]}}

      m = match(~r/^Game won by (?P<p>.+)$/, action) ->
        {:ok, %{event_type: "game_won", attacker: m["p"]}}

      m = match(~r/^(?P<p>.+?) won$/, action) ->
        {:ok, %{event_type: "game_won", attacker: m["p"]}}

      m = match(~r/^(?P<p>.+?) surrendered$/, action) ->
        {:ok, %{event_type: "surrendered", attacker: m["p"]}}

      m = match(~r/^(?P<p>.+?) timed out$/, action) ->
        {:ok, %{event_type: "timed_out", attacker: m["p"]}}

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
