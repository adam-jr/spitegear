defmodule Spitegear.HTML.Player do
  use Ecto.Schema

  @moduledoc """
  parse players from floki/html
  """
  require Logger

  @primary_key false
  embedded_schema do
    field(:name, :string)
    field(:slack_name, :string)

    field(:color, :string, virtual: true)
    field(:current_turn?, :boolean, virtual: true)
    field(:eliminated?, :boolean, virtual: true)
    field(:winner?, :boolean, virtual: true)
    field(:fogged?, :boolean, virtual: true)
  end

  @players [
    %{name: "pants off vant hof", slack_name: "@cvanthof85"},
    %{name: "adam jormp jomp", slack_name: "@atom.r"},
    %{name: "Kyjygyfyf", slack_name: "@json"},
    %{name: "ZachClash", slack_name: "@zachclash"},
    %{name: "Tallness", slack_name: "@zach"},
    %{name: "Hesh", slack_name: "@heshman45"},
    %{name: "dandodd", slack_name: "@dan"}
  ]

  def from_name(player_name), do: Enum.find(@players, &(&1.name == player_name))

  @doc """
  Parses players from html/Floki

  ## Examples

      iex> from_table_row(html)
      %Player{}

  """
  def from_table_row(tr) do
    name = player_name(tr)
    player = Enum.find(@players, &(&1.name == name))
    player = struct(__MODULE__, player)

    %{
      player
      | color: player_color(tr),
        current_turn?: current_turn?(tr),
        eliminated?: eliminated?(tr),
        winner?: winner?(tr),
        fogged?: fogged?(tr)
    }
  end

  defp current_turn?(tr) do
    {"tr", [], tds} = tr
    clock_td = Enum.at(tds, -2)

    case clock_td do
      {"td", [], [{"span", [{"id", _clock_num}], [_hd | _tl]}]} ->
        true

      {"td", [], [{"span", [{"id", _clock_num}], []}]} ->
        false

      {"td", [],
       [
         {"span", [{"title", "AutoBoot Pending"}, {"class", "boot_pending"}], [" "]},
         {"span", [{"id", _clock_num}], []}
       ]} ->
        false

      {"td", [],
       [
         {"span", [{"title", "AutoBoot Pending"}, {"class", "boot_pending"}], [" "]},
         {"span", [{"id", _clock_num}], _clock}
       ]} ->
        true

      _ ->
        false
    end
  end

  defp eliminated?(tr) do
    {"tr", [], tds} = tr
    eliminated_td = Enum.at(tds, -3)

    case eliminated_td do
      {"td", [], ["Eliminated"]} -> true
      _ -> false
    end
  end

  defp winner?(tr) do
    {"tr", [], tds} = tr
    winner_td = Enum.at(tds, -3)

    case winner_td do
      {"td", [], ["Winner"]} -> true
      _ -> false
    end
  end

  defp fogged?(tr) do
    {"tr", [], tds} = tr

    case Enum.at(tds, -3) do
      {"td", [], ["?"]} -> true
      _ -> false
    end
  end

  # Wargear marks each player's color on one of the row's td cells.
  # Older pages used a `bgcolor` HTML attribute; newer pages use an inline
  # `style="background-color:#rrggbb"` rule on the player-name td.
  # We check both forms and return the first color found, normalised to lowercase.
  defp player_color(tr) do
    {"tr", _attrs, tds} = tr

    Enum.find_value(tds, fn
      {"td", attrs, _} ->
        color_from_bgcolor(attrs) || color_from_style(attrs)

      _ ->
        nil
    end)
  end

  defp color_from_bgcolor(attrs) do
    case List.keyfind(attrs, "bgcolor", 0) do
      {_, color} when is_binary(color) and color != "" -> String.downcase(color)
      _ -> nil
    end
  end

  defp color_from_style(attrs) do
    case List.keyfind(attrs, "style", 0) do
      {_, style} when is_binary(style) ->
        case Regex.run(~r/background-color\s*:\s*(#[0-9a-fA-F]{3,8}|[a-zA-Z]+)/, style) do
          [_, color] -> String.downcase(color)
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp player_name(tr) do
    {"tr", [], tds} = tr
    player_td = Enum.at(tds, 2)

    [player_td]
    |> Floki.find("a")
    |> List.first()
    |> Floki.text()
    |> String.trim()
  end
end
