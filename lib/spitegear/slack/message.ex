defmodule Spitegear.Slack.Message do
  def text(:kind_reminder, turn),
    do:
      "<#{turn.player.slack_name}> #{reminder_text(turn.reminders)} http://www.spitegear.net/games/view/#{turn.game_id}"

  @spec text(
          :game_started | :next_turn,
          atom()
          | {atom() | %{:slack_name => any(), optional(any()) => any()}, any()}
          | %{:game_id => any(), :name => any(), optional(any()) => any()}
        ) :: <<_::64, _::_*8>>
  def text(:game_started, game),
    do:
      "I wuv you, waiting to start #{game.name} http://www.spitegear.net/games/view/#{game.game_id} 🧸💕"

  def text(:next_turn, {player, game_id}),
    do:
      "<#{player.slack_name}>, you are ON THE CLOCK http://www.spitegear.net/games/view/#{game_id}"

  def text(:player_died, player, game_id),
    do: "<#{player.slack_name}> died in http://www.spitegear.net/games/view/#{game_id}"

  def text(:game_winners, players, game_id),
    do: "#{slack_names(players)} won game ##{game_id}, huzzah #{winning_gif(game_id)} <@channel>"

  def text(:cards_traded, name, last_card), do: "#{name} just traded for #{last_card} units"

  def text(:list_wins, player, wins) do
    lines =
      wins
      |> Enum.map(fn win ->
        if win.game.utc_end_time do
          "<http://www.spitegear.net/games/view/#{win.game.game_id}|*#{win.game.name}* - #{DateTime.to_date(win.game.utc_end_time)}>"
        else
          "<http://www.spitegear.net/games/view/#{win.game.game_id}|*#{win.game.name}*>"
        end
      end)
      |> Enum.join("\n")

    """
    *Games Won by #{player.name}: #{Enum.count(wins)}*
    #{lines}
    """
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
