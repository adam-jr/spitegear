defmodule Spitegear.MessageTemplates do
  @moduledoc false
  import Ecto.Query
  alias Spitegear.MessageTemplate
  alias Spitegear.Repo
  alias Spitegear.Settings

  @keys ~w(next_turn kind_reminder_0 kind_reminder_1 kind_reminder_2 kind_reminder_3 kind_reminder_4 player_moving player_died game_winners game_winners_gif round_complete)a

  def all_keys, do: @keys

  # --- Default templates (used as fallback and shown in admin UI) ---

  def default_template(:next_turn),
    do:
      "*Round %{round}, turn %{turn_number}* — <%{player_slack}>, you're up in <%{game_url}|%{game_name}>"

  def default_template(:kind_reminder_0),
    do: "<%{player_slack}> I wuv you 🧸💕, can you go now? <%{game_url}|%{game_name}>"

  def default_template(:kind_reminder_1),
    do:
      "<%{player_slack}> I wuv you 🧸💕, did you see that it's your turn still? <%{game_url}|%{game_name}>"

  def default_template(:kind_reminder_2),
    do:
      "<%{player_slack}> I wuv you 🧸💕, you just gotta click the buttons, ok? 🧸💕 <%{game_url}|%{game_name}>"

  def default_template(:kind_reminder_3),
    do:
      "<%{player_slack}> I wuv you 🧸💕, you can always rest in the next game, or in the afterlife 🧸💕 <%{game_url}|%{game_name}>"

  def default_template(:kind_reminder_4),
    do:
      "<%{player_slack}> Strong bears also cry... strong bears also cry... 🧸 <%{game_url}|%{game_name}>"

  def default_template(:player_moving),
    do: "%{player_handle} is taking their turn! 👀"

  def default_template(:player_died),
    do: "<%{player_slack}> died in <%{game_url}|%{game_name}>"

  def default_template(:game_winners),
    do: "%{players_slack} won <%{game_url}|%{game_name}>, huzzah! :tada: <!channel>"

  def default_template(:game_winners_gif),
    do: "https://media.giphy.com/media/a0h7sAqON67nO/giphy.gif"

  def default_template(:round_complete),
    do: "⚔️ Round %{round} complete — round %{next_round} begins! <%{game_url}|%{game_name}>"

  def available_vars(:next_turn), do: ~w(player_slack round turn_number game_name game_url)

  def available_vars(key)
      when key in ~w(kind_reminder_0 kind_reminder_1 kind_reminder_2 kind_reminder_3 kind_reminder_4)a,
      do: ~w(player_slack reminders game_name game_url)

  def available_vars(:player_moving), do: ~w(player_handle)
  def available_vars(:player_died), do: ~w(player_slack game_name game_url)
  def available_vars(:game_winners), do: ~w(players_slack game_name game_url)
  def available_vars(:game_winners_gif), do: []
  def available_vars(:round_complete), do: ~w(round next_round game_name game_url)

  # --- High-level builders (called from GamePoller) ---

  def next_turn(player, game_id, round, turn_number, game_name) do
    render(
      :next_turn,
      %{
        player_slack: player.slack_name,
        round: round,
        turn_number: turn_number,
        game_name: game_name,
        game_url: game_url(game_id)
      },
      game_id
    )
  end

  def kind_reminder(turn, game_name) do
    key = :"kind_reminder_#{min(turn.reminders, 4)}"

    render(
      key,
      %{
        player_slack: turn.player.slack_name,
        reminders: turn.reminders,
        game_name: game_name,
        game_url: game_url(turn.game_id)
      },
      turn.game_id
    )
  end

  def player_moving(player, game_id) do
    render(
      :player_moving,
      %{
        player_handle: String.trim_leading(player.slack_name, "@")
      },
      game_id
    )
  end

  def player_died(player, game_id, game_name) do
    render(
      :player_died,
      %{
        player_slack: player.slack_name,
        game_name: game_name,
        game_url: game_url(game_id)
      },
      game_id
    )
  end

  def game_winners_blocks(players, game_id, game_name) do
    players_slack = Enum.map_join(players, " and ", &"<#{&1.slack_name}>")
    gif_url = render(:game_winners_gif, %{}, game_id)

    text =
      render(
        :game_winners,
        %{players_slack: players_slack, game_name: game_name, game_url: game_url(game_id)},
        game_id
      )

    blocks = [
      %{"type" => "section", "text" => %{"type" => "mrkdwn", "text" => text}},
      %{"type" => "image", "image_url" => gif_url, "alt_text" => "celebration"}
    ]

    {blocks, text}
  end

  def round_complete(game_id, round, game_name) do
    render(
      :round_complete,
      %{
        round: round,
        next_round: round + 1,
        game_name: game_name,
        game_url: game_url(game_id)
      },
      game_id
    )
  end

  # --- Test rendering ---

  def render_sample(key, game_id) when is_binary(key),
    do: render_sample(String.to_existing_atom(key), game_id)

  def render_sample(key, game_id) do
    slack_name = Settings.get("admin_slack_name") || "@testplayer"
    render(key, sample_vars(key, game_id, slack_name), game_id)
  end

  defp sample_vars(:next_turn, game_id, slack_name) do
    %{
      player_slack: slack_name,
      round: 3,
      turn_number: 42,
      game_name: "Test Game",
      game_url: game_url(game_id || "00000000")
    }
  end

  defp sample_vars(key, game_id, slack_name)
       when key in ~w(kind_reminder_0 kind_reminder_1 kind_reminder_2 kind_reminder_3 kind_reminder_4)a do
    n = key |> to_string() |> String.split("_") |> List.last() |> String.to_integer()

    %{
      player_slack: slack_name,
      reminders: n,
      game_name: "Test Game",
      game_url: game_url(game_id || "00000000")
    }
  end

  defp sample_vars(:player_moving, _game_id, slack_name) do
    %{player_handle: String.trim_leading(slack_name, "@")}
  end

  defp sample_vars(:player_died, game_id, slack_name) do
    %{
      player_slack: slack_name,
      game_name: "Test Game",
      game_url: game_url(game_id || "00000000")
    }
  end

  defp sample_vars(:game_winners, game_id, slack_name) do
    %{
      players_slack: "<#{slack_name}>",
      game_name: "Test Game",
      game_url: game_url(game_id || "00000000"),
      gif_url: render(:game_winners_gif, %{}, game_id)
    }
  end

  defp sample_vars(:round_complete, game_id, _slack_name) do
    %{round: 5, next_round: 6, game_name: "Test Game", game_url: game_url(game_id || "00000000")}
  end

  # --- DB access ---

  def get(key, game_id) do
    key = to_string(key)
    fetch(key, game_id) || fetch(key, nil)
  end

  def get_exact(key, game_id) do
    fetch(to_string(key), game_id)
  end

  def put(key, template_str, game_id \\ nil) do
    key = to_string(key)

    case fetch(key, game_id) do
      nil ->
        Repo.insert(%MessageTemplate{key: key, template: template_str, game_id: game_id})

      existing ->
        Repo.update(Ecto.Changeset.change(existing, template: template_str))
    end
  end

  def delete(key, game_id \\ nil) do
    key = to_string(key)

    case fetch(key, game_id) do
      nil -> :ok
      template -> Repo.delete(template) && :ok
    end
  end

  def list_global do
    Repo.all(from(t in MessageTemplate, where: is_nil(t.game_id)))
    |> Map.new(&{&1.key, &1.template})
  end

  def list_for_game(game_id) do
    Repo.all(from(t in MessageTemplate, where: t.game_id == ^game_id))
    |> Map.new(&{&1.key, &1.template})
  end

  # --- Private ---

  defp fetch(key, nil) do
    Repo.one(from(t in MessageTemplate, where: t.key == ^key and is_nil(t.game_id)))
  end

  defp fetch(key, game_id) do
    Repo.get_by(MessageTemplate, key: key, game_id: game_id)
  end

  defp render(key, vars, game_id) do
    template_str =
      case get(key, game_id) do
        nil -> default_template(key)
        t -> t.template
      end

    interpolate(template_str, vars)
  end

  defp interpolate(template, vars) do
    Enum.reduce(vars, template, fn {k, v}, acc ->
      String.replace(acc, "%{#{k}}", to_string(v))
    end)
  end

  defp game_url(game_id), do: "https://www.wargear.net/games/view/#{game_id}"
end
