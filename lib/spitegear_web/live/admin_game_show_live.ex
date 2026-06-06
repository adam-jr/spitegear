defmodule SpitegearWeb.AdminGameShowLive do
  use SpitegearWeb, :live_view
  require Logger
  alias Spitegear.GameLog.Processor
  alias Spitegear.GameLog.Stats
  alias Spitegear.Games
  alias Spitegear.LiveGameState.ViewScreens
  alias Spitegear.PubSub
  alias Spitegear.QuickChart
  alias Spitegear.Slack.API, as: SlackAPI
  alias Spitegear.Slack.Message

  @refresh_interval 10_000

  def mount(%{"game_id" => game_id}, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh, @refresh_interval)
    {:ok, assign(socket, load(game_id)) |> assign(chart_status: nil, log_fetch_status: nil)}
  end

  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_interval)
    {:noreply, assign(socket, load(socket.assigns.game_id))}
  end

  def handle_info({:chart_result, :ok}, socket) do
    {:noreply, assign(socket, chart_status: :sent)}
  end

  def handle_info({:chart_result, {:error, reason}}, socket) do
    {:noreply, assign(socket, chart_status: {:error, reason})}
  end

  def handle_info({:log_fetch_result, {:ok, counts}}, socket) do
    Logger.info("fetch_log #{socket.assigns.game_id} done: #{inspect(counts)}")
    updates = Map.merge(load(socket.assigns.game_id), %{log_fetch_status: {:ok, counts}})
    {:noreply, assign(socket, updates)}
  end

  def handle_info({:log_fetch_result, {:error, reason}}, socket) do
    Logger.error("fetch_log #{socket.assigns.game_id} error: #{inspect(reason)}")
    {:noreply, assign(socket, log_fetch_status: {:error, reason})}
  end

  def handle_event("start_poller", _params, socket) do
    Games.start_poller(socket.assigns.game_id)
    {:noreply, assign(socket, load(socket.assigns.game_id))}
  end

  def handle_event("stop_poller", _params, socket) do
    Games.stop_poller(socket.assigns.game_id)
    {:noreply, assign(socket, load(socket.assigns.game_id))}
  end

  def handle_event("start_new_poller", _params, socket) do
    Games.start_new_poller(socket.assigns.game_id)
    {:noreply, assign(socket, load(socket.assigns.game_id))}
  end

  def handle_event("stop_new_poller", _params, socket) do
    Games.stop_new_poller(socket.assigns.game_id)
    {:noreply, assign(socket, load(socket.assigns.game_id))}
  end

  def handle_event("fetch_log", _params, socket) do
    game_id = socket.assigns.game_id
    lv = self()
    Logger.info("fetch_log #{game_id} started")

    Task.start(fn ->
      Logger.info("fetch_log #{game_id} task running")
      result = Processor.refetch_and_process(game_id)
      Logger.info("fetch_log #{game_id} task complete: #{inspect(result)}")
      send(lv, {:log_fetch_result, result})
    end)

    {:noreply, assign(socket, log_fetch_status: :fetching)}
  end

  def handle_event("send_test_stats", _params, socket) do
    blocks =
      Message.blocks(
        :turn_stats,
        socket.assigns.stats,
        socket.assigns.game_id,
        socket.assigns.completed_rounds
      )

    fallback =
      Message.text(
        :turn_stats,
        socket.assigns.stats,
        socket.assigns.game_id,
        socket.assigns.completed_rounds
      )

    PubSub.msg(:spitegear_test, type: :turn_stats, payload: {blocks, fallback})
    {:noreply, socket}
  end

  def handle_event("send_chart_to_slack", _params, socket) do
    series = socket.assigns.net_units_series
    game_id = socket.assigns.game_id
    lv = self()

    Task.start(fn ->
      result =
        case QuickChart.render_net_units(series) do
          {:ok, png} -> SlackAPI.upload_file(png, "net-units-#{game_id}.png", :spitegear_test)
          err -> err
        end

      send(lv, {:chart_result, result})
    end)

    {:noreply, assign(socket, chart_status: :sending)}
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
    new_poller_alive = Games.new_poller_alive?(game_id)
    player_statuses = Games.list_player_statuses(game_id)
    net_units_series = Stats.enriched_net_units_series(game_id)
    units_received_series = Stats.units_received_series(game_id)
    units_killed_series = Stats.units_killed_series(game_id)
    luck_ratio_series = Stats.luck_ratio_series(game_id)
    attacks_received_series = Stats.attacks_received_series(game_id)
    jormp_jomps_received_series = Stats.jormp_jomps_received_series(game_id)
    jormp_jomps_delivered_series = Stats.jormp_jomps_delivered_series(game_id)
    placement_scores = Stats.placement_scores(game_id)
    view_screen = ViewScreens.get_latest(game_id)

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
      new_poller_alive: new_poller_alive,
      player_statuses: player_statuses,
      net_units_series: net_units_series,
      units_received_series: units_received_series,
      units_killed_series: units_killed_series,
      luck_ratio_series: luck_ratio_series,
      attacks_received_series: attacks_received_series,
      jormp_jomps_received_series: jormp_jomps_received_series,
      jormp_jomps_delivered_series: jormp_jomps_delivered_series,
      placement_scores: placement_scores,
      view_screen: view_screen
    }
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto mt-16 p-6 flex gap-8 items-start">
      <%!-- Sidebar: turn order --%>
      <%= if @view_screen && Enum.any?(@view_screen.players || []) do %>
        <aside class="w-44 shrink-0 flex flex-col gap-1">
          <h2 class="text-xs font-semibold uppercase tracking-widest text-gray-400 mb-2">
            Turn Order
          </h2>
          <%= for {player, idx} <- Enum.with_index(@view_screen.players, 1) do %>
            <% name = player["name"] %>
            <% active = name == @view_screen.current_player_name %>
            <% eliminated = name in (@view_screen.eliminated || []) %>
            <div class={[
              "flex items-center gap-2 px-3 py-2 rounded-lg text-sm",
              cond do
                active -> "bg-blue-50 border border-blue-200"
                eliminated -> "opacity-40"
                true -> ""
              end
            ]}>
              <span class="text-xs text-gray-400 tabular-nums w-4 shrink-0">{idx}</span>
              <span class={[
                "truncate",
                if(active, do: "font-semibold text-blue-700", else: "text-gray-700"),
                if(eliminated, do: "line-through", else: "")
              ]}>
                {name}
              </span>
              <%= if eliminated do %>
                <span class="text-gray-400 shrink-0">✕</span>
              <% end %>
              <%= if active do %>
                <span class="w-1.5 h-1.5 rounded-full bg-blue-500 shrink-0 ml-auto"></span>
              <% end %>
            </div>
          <% end %>
        </aside>
      <% end %>

      <%!-- Main content --%>
      <div class="flex-1 flex flex-col gap-10 min-w-0">
        <div class="flex items-center justify-between">
          <div>
            <a href="/admin/games" class="text-sm text-blue-600 hover:underline">← Games</a>
            <h1 class="text-2xl font-bold mt-1">
              {if @game, do: @game.game_name, else: "Game #{@game_id}"}
            </h1>
            <%= if @game && @game.board_name do %>
              <p class="text-sm text-gray-500">{@game.board_name}</p>
            <% end %>
          </div>
          <div class="flex items-center gap-3">
            <span class={
              if @poller_alive,
                do: "text-green-600 text-sm font-medium",
                else: "text-gray-400 text-sm"
            }>
              {if @poller_alive, do: "● polling", else: "○ stopped"}
            </span>
            <%= if @poller_alive do %>
              <button phx-click="stop_poller" class="text-sm text-red-600 hover:underline">
                Stop
              </button>
            <% else %>
              <button phx-click="start_poller" class="text-sm text-blue-600 hover:underline">
                Start
              </button>
            <% end %>
            <span class="text-gray-300">|</span>
            <span class={
              if @new_poller_alive,
                do: "text-green-600 text-sm font-medium",
                else: "text-gray-400 text-sm"
            }>
              {if @new_poller_alive, do: "● new", else: "○ new"}
            </span>
            <%= if @new_poller_alive do %>
              <button phx-click="stop_new_poller" class="text-sm text-red-600 hover:underline">
                Stop
              </button>
            <% else %>
              <button phx-click="start_new_poller" class="text-sm text-blue-600 hover:underline">
                Start
              </button>
            <% end %>
            <button
              phx-click="fetch_log"
              disabled={@log_fetch_status == :fetching}
              class="text-sm text-blue-600 hover:underline disabled:opacity-50"
            >
              {if @log_fetch_status == :fetching, do: "Fetching…", else: "Fetch Log"}
            </button>
            <%= case @log_fetch_status do %>
              <% {:ok, counts} -> %>
                <span class="text-sm text-green-600">
                  +{counts.new_events} new
                </span>
              <% {:error, reason} -> %>
                <span class="text-sm text-red-600">Error: {inspect(reason)}</span>
              <% _ -> %>
            <% end %>
            <a href={"/admin/games/#{@game_id}/log"} class="text-sm text-blue-600 hover:underline">
              Log →
            </a>
            <a
              href={"/admin/games/#{@game_id}/templates"}
              class="text-sm text-blue-600 hover:underline"
            >
              Templates →
            </a>
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
            <h2 class="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-3">
              Current Turn
            </h2>
            <%= if @turn do %>
              <p class="text-xl font-bold">{@turn.player.name}</p>
              <p class="text-sm text-gray-500">{@turn.player.slack_name}</p>
              <dl class="mt-3 grid grid-cols-2 gap-x-4 gap-y-1 text-sm">
                <dt class="text-gray-500">Started</dt>
                <dd>{format_datetime(@turn.started)}</dd>
                <dt class="text-gray-500">Duration</dt>
                <dd>{elapsed(@turn.started)}</dd>
                <dt class="text-gray-500">Reminders</dt>
                <dd>{@turn.reminders}</dd>
              </dl>
            <% else %>
              <p class="text-gray-400 text-sm">No active turn</p>
            <% end %>
          </div>

          <div class="border border-gray-200 rounded p-4">
            <h2 class="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-3">
              Game Stats
            </h2>
            <dl class="grid grid-cols-2 gap-x-4 gap-y-1 text-sm">
              <dt class="text-gray-500">Game ID</dt>
              <dd class="font-mono">{@game_id}</dd>
              <dt class="text-gray-500">Completed turns</dt>
              <dd>{@total_turns}</dd>
              <%= if @poller_turn_id do %>
                <dt class="text-gray-500">Turn ID</dt>
                <dd class="font-mono">{@poller_turn_id}</dd>
              <% end %>
              <%= if @game && @game.created do %>
                <dt class="text-gray-500">Created</dt>
                <dd>{@game.created}</dd>
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
                  if(p.alive,
                    do: "bg-green-100 text-green-800",
                    else: "bg-gray-100 text-gray-500 line-through"
                  )
                ]}>
                  <span class={if p.alive, do: "text-green-500", else: "text-gray-400"}>
                    {if p.alive, do: "●", else: "✕"}
                  </span>
                  {p.player_name}
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
                    <td class="py-1 pr-4">{s.player_name}</td>
                    <td class="py-1 pr-4">{s.count}</td>
                    <td class="py-1 pr-4">{format_duration(s.avg_seconds)}</td>
                    <td class="py-1 pr-4">{format_duration(s.fastest_seconds)}</td>
                    <td class="py-1">{format_duration(s.slowest_seconds)}</td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </section>
        <% end %>

        <%!-- Net Units Chart --%>
        <%= if map_size(@net_units_series) > 0 do %>
          <section>
            <div class="flex items-center justify-between mb-3">
              <h2 class="text-lg font-semibold">Net Units Over Time</h2>
              <div class="flex items-center gap-3">
                <button
                  phx-click={JS.dispatch("reset-zoom", to: "#net-units-chart")}
                  class="text-sm text-gray-500 hover:text-gray-800"
                >
                  Reset Zoom
                </button>
                <button
                  phx-click="send_chart_to_slack"
                  disabled={@chart_status == :sending}
                  class="text-sm text-blue-600 hover:underline disabled:opacity-50"
                >
                  {if @chart_status == :sending, do: "Sending…", else: "Send to #spitegear-test"}
                </button>
                <%= case @chart_status do %>
                  <% :sent -> %>
                    <span class="text-sm text-green-600">✓ Sent</span>
                  <% {:error, reason} -> %>
                    <span class="text-sm text-red-600">Error: {reason}</span>
                  <% _ -> %>
                <% end %>
              </div>
            </div>
            <p class="text-xs text-gray-400 mb-2">Drag to zoom · double-click to reset</p>
            <div class="relative h-[500px] border border-gray-200 rounded p-2">
              <canvas
                id="net-units-chart"
                phx-hook="NetUnitsChart"
                data-series={Jason.encode!(@net_units_series)}
                data-colors={Jason.encode!((@game && @game.player_colors) || %{})}
              >
              </canvas>
            </div>
            <%= if map_size(@placement_scores) > 0 do %>
              <div class="mt-4">
                <h3 class="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-2">
                  Placement
                </h3>
                <table class="w-full text-sm">
                  <tbody>
                    <%= for {{player, score}, rank} <-
                        @placement_scores
                        |> Enum.sort_by(&elem(&1, 1), :desc)
                        |> Enum.with_index(1) do %>
                      <tr class="border-b border-gray-100">
                        <td class="py-1.5 pr-3 text-gray-400 w-8 tabular-nums">#{rank}</td>
                        <td class="py-1.5 pr-4 font-medium">{player}</td>
                        <td class="py-1.5 text-right text-gray-600 font-mono tabular-nums">
                          {format_score(score)}
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% end %>
          </section>
        <% end %>

        <%!-- Units Received Chart --%>
        <%= if map_size(@units_received_series) > 0 do %>
          <section>
            <div class="flex items-center justify-between mb-3">
              <h2 class="text-lg font-semibold">Units Received Over Time</h2>
              <button
                phx-click={JS.dispatch("reset-zoom", to: "#units-received-chart")}
                class="text-sm text-gray-500 hover:text-gray-800"
              >
                Reset Zoom
              </button>
            </div>
            <p class="text-xs text-gray-400 mb-2">Drag to zoom · double-click to reset</p>
            <div class="relative h-[500px] border border-gray-200 rounded p-2">
              <canvas
                id="units-received-chart"
                phx-hook="NetUnitsChart"
                data-series={Jason.encode!(@units_received_series)}
                data-colors={Jason.encode!((@game && @game.player_colors) || %{})}
              >
              </canvas>
            </div>
          </section>
        <% end %>

        <%!-- Units Killed Chart --%>
        <%= if map_size(@units_killed_series) > 0 do %>
          <section>
            <div class="flex items-center justify-between mb-3">
              <h2 class="text-lg font-semibold">Units Killed Over Time</h2>
              <button
                phx-click={JS.dispatch("reset-zoom", to: "#units-killed-chart")}
                class="text-sm text-gray-500 hover:text-gray-800"
              >
                Reset Zoom
              </button>
            </div>
            <p class="text-xs text-gray-400 mb-2">Drag to zoom · double-click to reset</p>
            <div class="relative h-[500px] border border-gray-200 rounded p-2">
              <canvas
                id="units-killed-chart"
                phx-hook="NetUnitsChart"
                data-series={Jason.encode!(@units_killed_series)}
                data-colors={Jason.encode!((@game && @game.player_colors) || %{})}
              >
              </canvas>
            </div>
          </section>
        <% end %>

        <%!-- Luck Ratio Chart --%>
        <%= if map_size(@luck_ratio_series) > 0 do %>
          <section>
            <div class="flex items-center justify-between mb-3">
              <h2 class="text-lg font-semibold">Luck Ratio Over Time</h2>
              <button
                phx-click={JS.dispatch("reset-zoom", to: "#luck-ratio-chart")}
                class="text-sm text-gray-500 hover:text-gray-800"
              >
                Reset Zoom
              </button>
            </div>
            <p class="text-xs text-gray-400 mb-2">
              Cumulative (defender losses − attacker losses) per attacker. Positive = lucky, negative = unlucky. Drag to zoom · double-click to reset
            </p>
            <div class="relative h-[500px] border border-gray-200 rounded p-2">
              <canvas
                id="luck-ratio-chart"
                phx-hook="NetUnitsChart"
                data-series={Jason.encode!(@luck_ratio_series)}
                data-colors={Jason.encode!((@game && @game.player_colors) || %{})}
              >
              </canvas>
            </div>
          </section>
        <% end %>

        <%!-- Attacks Received Chart --%>
        <%= if map_size(@attacks_received_series) > 0 do %>
          <section>
            <div class="flex items-center justify-between mb-3">
              <h2 class="text-lg font-semibold">Attacks Received Over Time</h2>
              <button
                phx-click={JS.dispatch("reset-zoom", to: "#attacks-received-chart")}
                class="text-sm text-gray-500 hover:text-gray-800"
              >
                Reset Zoom
              </button>
            </div>
            <p class="text-xs text-gray-400 mb-2">
              Cumulative attacker dice directed at each player — a proxy for attacking pressure received. Drag to zoom · double-click to reset
            </p>
            <div class="relative h-[500px] border border-gray-200 rounded p-2">
              <canvas
                id="attacks-received-chart"
                phx-hook="NetUnitsChart"
                data-series={Jason.encode!(@attacks_received_series)}
                data-colors={Jason.encode!((@game && @game.player_colors) || %{})}
              >
              </canvas>
            </div>
          </section>
        <% end %>

        <%!-- Jormp Jomps Received Chart --%>
        <%= if map_size(@jormp_jomps_received_series) > 0 do %>
          <section>
            <div class="flex items-center justify-between mb-3">
              <h2 class="text-lg font-semibold">Cumulative Jormp Jomps Received</h2>
              <button
                phx-click={JS.dispatch("reset-zoom", to: "#jormp-jomps-received-chart")}
                class="text-sm text-gray-500 hover:text-gray-800"
              >
                Reset Zoom
              </button>
            </div>
            <p class="text-xs text-gray-400 mb-2">
              3-dice attack → 2 attacker losses, 0 defender losses. The attacker got jormp jomped. Drag to zoom · double-click to reset
            </p>
            <div class="relative h-[500px] border border-gray-200 rounded p-2">
              <canvas
                id="jormp-jomps-received-chart"
                phx-hook="NetUnitsChart"
                data-series={Jason.encode!(@jormp_jomps_received_series)}
                data-colors={Jason.encode!((@game && @game.player_colors) || %{})}
              >
              </canvas>
            </div>
          </section>
        <% end %>

        <%!-- Jormp Jomps Delivered Chart --%>
        <%= if map_size(@jormp_jomps_delivered_series) > 0 do %>
          <section>
            <div class="flex items-center justify-between mb-3">
              <h2 class="text-lg font-semibold">Cumulative Jormp Jomps Delivered</h2>
              <button
                phx-click={JS.dispatch("reset-zoom", to: "#jormp-jomps-delivered-chart")}
                class="text-sm text-gray-500 hover:text-gray-800"
              >
                Reset Zoom
              </button>
            </div>
            <p class="text-xs text-gray-400 mb-2">
              Times this player's defense caused 2 attacker losses with 0 defender losses on a 3-dice attack. Drag to zoom · double-click to reset
            </p>
            <div class="relative h-[500px] border border-gray-200 rounded p-2">
              <canvas
                id="jormp-jomps-delivered-chart"
                phx-hook="NetUnitsChart"
                data-series={Jason.encode!(@jormp_jomps_delivered_series)}
                data-colors={Jason.encode!((@game && @game.player_colors) || %{})}
              >
              </canvas>
            </div>
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
                    <td class="py-1 pr-4">{t.player_name}</td>
                    <td class="py-1 pr-4">{format_datetime(t.started)}</td>
                    <td class="py-1">{format_duration(DateTime.diff(t.ended, t.started))}</td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </section>
        <% end %>
      </div>
    </div>
    """
  end

  defp format_score(n) when n < 0, do: "-" <> format_score(-n)

  defp format_score(n) do
    n
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.map_join(",", &Enum.join/1)
    |> String.reverse()
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
