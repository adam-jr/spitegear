defmodule Spitegear.Slack.Message do
  def text(:kind_reminder, turn),
    do:
      "<#{turn.player.slack_name}> #{reminder_text(turn.reminders)} https://www.wargear.net/games/view/#{turn.game_id}"

  def text(:game_started, game),
    do:
      "I wuv you, waiting to start #{game.name} https://www.wargear.net/games/view/#{game.game_id} 🧸💕"

  def text(:next_turn, {player, game_id}),
    do:
      "<#{player.slack_name}>, you are ON THE CLOCK https://www.wargear.net/games/view/#{game_id}"

  def text(:player_moving, player),
    do: "<#{player.slack_name}> is taking their turn! 👀"

  def text(:player_died, player, game_id),
    do: "<#{player.slack_name}> died in https://www.wargear.net/games/view/#{game_id}"

  def text(:game_winners, players, game_id),
    do: "#{slack_names(players)} won game ##{game_id}, huzzah #{winning_gif(game_id)} <@channel>"

  def text(:turn_stats, history, game_id) do
    lines =
      history
      |> Enum.group_by(& &1.player_name)
      |> Enum.map(fn {name, turns} ->
        durations = Enum.map(turns, & &1.duration_seconds)
        avg = Enum.sum(durations) |> div(length(durations))
        fastest = Enum.min(durations)
        slowest = Enum.max(durations)
        "#{name}: avg #{format_duration(avg)}, fastest #{format_duration(fastest)}, slowest #{format_duration(slowest)}"
      end)
      |> Enum.sort()
      |> Enum.join("\n")

    "*Turn stats after #{length(history)} turns — game ##{game_id}*\n#{lines}"
  end

  def text(:cards_traded, name, last_card), do: "#{name} just traded for #{last_card} units"

  def text(:list_wins, player, wins) do
    lines =
      wins
      |> Enum.map(fn win ->
        if win.game.utc_end_time do
          "<https://www.wargear.net/games/view/#{win.game.game_id}|*#{win.game.name}* - #{DateTime.to_date(win.game.utc_end_time)}>"
        else
          "<https://www.wargear.net/games/view/#{win.game.game_id}|*#{win.game.name}*>"
        end
      end)
      |> Enum.join("\n")

    """
    *Games Won by #{player.name}: #{Enum.count(wins)}*
    #{lines}
    """
  end

  defp format_duration(seconds) when seconds < 60, do: "#{seconds}s"

  defp format_duration(seconds) when seconds < 3600 do
    "#{div(seconds, 60)}m"
  end

  defp format_duration(seconds) do
    h = div(seconds, 3600)
    m = div(rem(seconds, 3600), 60)
    if m > 0, do: "#{h}h#{m}m", else: "#{h}h"
  end

  defp slack_names(players) do
    Enum.map(players, fn player ->
      "<#{player.slack_name}>"
    end)
    |> Enum.join(" and ")
  end

  defp winning_gif(_game_id) do
    "https://media.giphy.com/media/a0h7sAqON67nO/giphy.gif"
  end

  defp reminder_text(reminders) do
    case reminders do
      0 -> "I wuv you 🧸💕, can you go now?"
      1 -> "I wuv you 🧸💕, did you see that it's your turn still?"
      2 -> "I wuv you 🧸💕, you just gotta click the buttons, ok? 🧸💕"
      3 -> "I wuv you 🧸💕, you can always rest in the next game, or in the afterlife 🧸💕"
      _ -> "Strong bears also cry... strong bears also cry... 🧸"
    end
  end
end
