defmodule SpitegearWeb.AdminGameShowLive do
  use SpitegearWeb, :live_view
  alias Spitegear.Games
  alias Spitegear.MessageTemplates
  alias Spitegear.PubSub
  alias Spitegear.Slack.Message

  @refresh_interval 10_000

  def mount(%{"game_id" => game_id}, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh, @refresh_interval)
    {:ok, assign(socket, load(game_id))}
  end

  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_interval)
    {:noreply, assign(socket, load(socket.assigns.game_id))}
  end

  def handle_event("save_game_template", %{"key" => key, "template" => template}, socket) do
    game_id = socket.assigns.game_id
    MessageTemplates.put(key, template, game_id)

    {:noreply,
     assign(socket,
       game_templates: MessageTemplates.list_for_game(game_id),
       saved_template: key
     )}
  end

  def handle_event("reset_game_template", %{"key" => key}, socket) do
    game_id = socket.assigns.game_id
    MessageTemplates.delete(key, game_id)

    {:noreply,
     assign(socket,
       game_templates: MessageTemplates.list_for_game(game_id),
       saved_template: nil
     )}
  end

  def handle_event("start_poller", _params, socket) do
    Games.start_poller(socket.assigns.game_id)
    {:noreply, assign(socket, load(socket.assigns.game_id))}
  end

  def handle_event("stop_poller", _params, socket) do
    Games.stop_poller(socket.assigns.game_id)
    {:noreply, assign(socket, load(socket.assigns.game_id))}
  end

  def handle_event("send_test_stats", _params, socket) do
    blocks = Message.blocks(:turn_stats, socket.assigns.stats, socket.assigns.game_id, socket.assigns.completed_rounds)
    fallback = Message.text(:turn_stats, socket.assigns.stats, socket.assigns.game_id, socket.assigns.completed_rounds)
    PubSub.msg(:spitegear_test, type: :turn_stats, payload: {blocks, fallback})
    {:noreply, socket}
  end

  defp load(game_id) do
    game = Games.get_game(game_id)
    turn = Games.get_current_turn(game_id)
    history = Games.list_turn_history(game_id)
    stats = Games.turn_stats(game_id)
    total_turns = Games.completed_turn_count(game_id)
    completed_rounds = Games.completed_rounds(game_id)
    poller_alive = Games.poller_alive?(game_id)
    poller_turn_id = Games.poller_turn_id(game_id)
    player_statuses = Games.list_player_statuses(game_id)
    game_templates = MessageTemplates.list_for_game(game_id)
    global_templates = MessageTemplates.list_global()

    %{
      game_id: game_id,
      game: game,
      turn: turn,
      history: history,
      stats: stats,
      total_turns: total_turns,
      completed_rounds: completed_rounds,
      poller_alive: poller_alive,
      poller_turn_id: poller_turn_id,
      player_statuses: player_statuses,
      game_templates: game_templates,
      global_templates: global_templates,
      saved_template: nil
    }
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto mt-16 p-6 flex flex-col gap-10">
      <div class="flex items-center justify-between">
        <div>
          <a href="/admin/games" class="text-sm text-blue-600 hover:underline">← Games</a>
          <h1 class="text-2xl font-bold mt-1">
            <%= if @game, do: @game.game_name, else: "Game #{@game_id}" %>
          </h1>
          <%= if @game && @game.board_name do %>
            <p class="text-sm text-gray-500"><%= @game.board_name %></p>
          <% end %>
        </div>
        <div class="flex items-center gap-3">
          <span class={if @poller_alive, do: "text-green-600 text-sm font-medium", else: "text-gray-400 text-sm"}>
            <%= if @poller_alive, do: "● polling", else: "○ stopped" %>
          </span>
          <%= if @poller_alive do %>
            <button phx-click="stop_poller" class="text-sm text-red-600 hover:underline">Stop</button>
          <% else %>
            <button phx-click="start_poller" class="text-sm text-blue-600 hover:underline">Start</button>
          <% end %>
          <a
            href={"https://www.wargear.net/games/view/#{@game_id}"}
            target="_blank"
            class="text-sm text-blue-600 hover:underline"
          >
            wargear.net ↗
          </a>
        </div>
      </div>

      <section class="grid grid-cols-2 gap-6">
        <div class="border border-gray-200 rounded p-4">
          <h2 class="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-3">Current Turn</h2>
          <%= if @turn do %>
            <p class="text-xl font-bold"><%= @turn.player.name %></p>
            <p class="text-sm text-gray-500"><%= @turn.player.slack_name %></p>
            <dl class="mt-3 grid grid-cols-2 gap-x-4 gap-y-1 text-sm">
              <dt class="text-gray-500">Started</dt>
              <dd><%= format_datetime(@turn.started) %></dd>
              <dt class="text-gray-500">Duration</dt>
              <dd><%= elapsed(@turn.started) %></dd>
              <dt class="text-gray-500">Reminders</dt>
              <dd><%= @turn.reminders %></dd>
            </dl>
          <% else %>
            <p class="text-gray-400 text-sm">No active turn</p>
          <% end %>
        </div>

        <div class="border border-gray-200 rounded p-4">
          <h2 class="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-3">Game Stats</h2>
          <dl class="grid grid-cols-2 gap-x-4 gap-y-1 text-sm">
            <dt class="text-gray-500">Game ID</dt>
            <dd class="font-mono"><%= @game_id %></dd>
            <dt class="text-gray-500">Completed turns</dt>
            <dd><%= @total_turns %></dd>
            <%= if @poller_turn_id do %>
              <dt class="text-gray-500">Turn ID</dt>
              <dd class="font-mono"><%= @poller_turn_id %></dd>
            <% end %>
            <%= if @game && @game.created do %>
              <dt class="text-gray-500">Created</dt>
              <dd><%= @game.created %></dd>
            <% end %>
          </dl>
        </div>
      </section>

      <%= if Enum.any?(@player_statuses) do %>
        <section>
          <h2 class="text-lg font-semibold mb-3">Players</h2>
          <div class="flex flex-wrap gap-2">
            <%= for p <- @player_statuses do %>
              <span class={[
                "inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-sm font-medium",
                if(p.alive, do: "bg-green-100 text-green-800", else: "bg-gray-100 text-gray-500 line-through")
              ]}>
                <span class={if p.alive, do: "text-green-500", else: "text-gray-400"}>
                  <%= if p.alive, do: "●", else: "✕" %>
                </span>
                <%= p.player_name %>
              </span>
            <% end %>
          </div>
        </section>
      <% end %>

      <%= if Enum.any?(@stats) do %>
        <section>
          <div class="flex items-center justify-between mb-3">
            <h2 class="text-lg font-semibold">Turn Stats</h2>
            <button phx-click="send_test_stats" class="text-sm text-blue-600 hover:underline">
              Send to #spitegear-test
            </button>
          </div>
          <table class="w-full text-sm border-collapse">
            <thead>
              <tr class="text-left border-b border-gray-200">
                <th class="pb-2 pr-4">Player</th>
                <th class="pb-2 pr-4">Turns</th>
                <th class="pb-2 pr-4">Avg</th>
                <th class="pb-2 pr-4">Fastest</th>
                <th class="pb-2">Slowest</th>
              </tr>
            </thead>
            <tbody>
              <%= for s <- @stats do %>
                <tr class="border-b border-gray-100">
                  <td class="py-1 pr-4"><%= s.player_name %></td>
                  <td class="py-1 pr-4"><%= s.count %></td>
                  <td class="py-1 pr-4"><%= format_duration(s.avg_seconds) %></td>
                  <td class="py-1 pr-4"><%= format_duration(s.fastest_seconds) %></td>
                  <td class="py-1"><%= format_duration(s.slowest_seconds) %></td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </section>
      <% end %>

      <%= if Enum.any?(@history) do %>
        <section>
          <h2 class="text-lg font-semibold mb-3">Recent Turns</h2>
          <table class="w-full text-sm border-collapse">
            <thead>
              <tr class="text-left border-b border-gray-200">
                <th class="pb-2 pr-4">Player</th>
                <th class="pb-2 pr-4">Started</th>
                <th class="pb-2">Duration</th>
              </tr>
            </thead>
            <tbody>
              <%= for t <- @history do %>
                <tr class="border-b border-gray-100">
                  <td class="py-1 pr-4"><%= t.player_name %></td>
                  <td class="py-1 pr-4"><%= format_datetime(t.started) %></td>
                  <td class="py-1"><%= format_duration(DateTime.diff(t.ended, t.started)) %></td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </section>
      <% end %>
      <section>
        <h2 class="text-lg font-semibold mb-3">Message Templates</h2>
        <p class="text-sm text-gray-500 mb-4">
          Game-specific overrides. Falls back to global defaults if not set.
          Use <code class="bg-gray-100 px-1 rounded">%{"{var}"}</code> for variables.
        </p>
        <div class="flex flex-col gap-6">
          <%= for key <- MessageTemplates.all_keys() do %>
            <% key_str = to_string(key) %>
            <% game_custom = Map.get(@game_templates, key_str) %>
            <% global_custom = Map.get(@global_templates, key_str) %>
            <div class="border border-gray-200 rounded p-4">
              <div class="flex items-center justify-between mb-1">
                <span class="text-sm font-medium font-mono"><%= key_str %></span>
                <div class="flex items-center gap-3">
                  <%= cond do %>
                    <% game_custom -> %>
                      <span class="text-xs text-blue-600 font-medium">game override</span>
                      <button
                        phx-click="reset_game_template"
                        phx-value-key={key_str}
                        class="text-xs text-red-500 hover:underline"
                      >
                        Reset to <%= if global_custom, do: "global", else: "default" %>
                      </button>
                    <% global_custom -> %>
                      <span class="text-xs text-yellow-600 font-medium">global</span>
                    <% true -> %>
                      <span class="text-xs text-gray-400">default</span>
                  <% end %>
                </div>
              </div>
              <p class="text-xs text-gray-400 mb-2">
                vars: <%= Enum.join(MessageTemplates.available_vars(key), ", ") %>
              </p>
              <form phx-submit="save_game_template" class="flex flex-col gap-2">
                <input type="hidden" name="key" value={key_str} />
                <textarea
                  name="template"
                  rows="2"
                  class="w-full font-mono text-sm border border-gray-300 rounded p-2"
                ><%= game_custom || global_custom || MessageTemplates.default_template(key) %></textarea>
                <div class="flex items-center gap-3">
                  <button type="submit" class="text-sm text-blue-600 hover:underline">Save</button>
                  <%= if @saved_template == key_str do %>
                    <span class="text-green-600 text-xs">Saved</span>
                  <% end %>
                </div>
              </form>
            </div>
          <% end %>
        </div>
      </section>
    </div>
    """
  end

  defp format_datetime(nil), do: "—"

  defp format_datetime(dt) do
    dt
    |> DateTime.shift_zone!("America/Chicago")
    |> Calendar.strftime("%b %d %I:%M %p")
  end

  defp elapsed(nil), do: "—"

  defp elapsed(started) do
    diff = DateTime.diff(DateTime.utc_now(), started)
    format_duration(diff)
  end

  defp format_duration(seconds) when seconds < 60, do: "#{seconds}s"

  defp format_duration(seconds) when seconds < 3600 do
    "#{div(seconds, 60)}m"
  end

  defp format_duration(seconds) do
    h = div(seconds, 3600)
    m = div(rem(seconds, 3600), 60)
    if m > 0, do: "#{h}h #{m}m", else: "#{h}h"
  end
end
