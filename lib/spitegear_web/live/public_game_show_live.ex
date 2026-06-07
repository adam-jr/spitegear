defmodule SpitegearWeb.PublicGameShowLive do
  use SpitegearWeb, :live_view
  alias Spitegear.GameLog.Stats
  alias Spitegear.Games
  alias Spitegear.LiveGameState.Turns
  alias Spitegear.LiveGameState.ViewScreens

  def mount(%{"game_id" => game_id}, _session, socket) do
    case Games.get_game(game_id) do
      nil ->
        {:ok, push_navigate(socket, to: "/")}

      game ->
        log_summary = Stats.game_log_summary(game_id)
        net_units_series = Stats.enriched_net_units_series(game_id)
        units_received_series = Stats.units_received_series(game_id)
        units_killed_series = Stats.units_killed_series(game_id)
        luck_ratio_series = Stats.luck_ratio_series(game_id)
        attacks_received_series = Stats.attacks_received_series(game_id)
        jormp_jomps_received_series = Stats.jormp_jomps_received_series(game_id)
        jormp_jomps_delivered_series = Stats.jormp_jomps_delivered_series(game_id)
        placement_scores = Stats.placement_scores(game_id)
        days = game_duration_days(game)
        view_screen = ViewScreens.get_latest(game_id)
        current_turn = Turns.get_open_turn(game_id)
        round_info = Turns.round_info(game_id)

        {current_round, turn_within_round} =
          if current_turn do
            k = Map.get(round_info.turn_counts, current_turn.player_name, 0)

            position =
              view_screen &&
                Enum.find_index(view_screen.players, &(&1.name == current_turn.player_name))

            {k + 1, position && position + 1}
          else
            {nil, nil}
          end

        {:ok,
         assign(socket,
           game_id: game_id,
           game: game,
           log_summary: log_summary,
           net_units_series: net_units_series,
           units_received_series: units_received_series,
           units_killed_series: units_killed_series,
           luck_ratio_series: luck_ratio_series,
           attacks_received_series: attacks_received_series,
           jormp_jomps_received_series: jormp_jomps_received_series,
           jormp_jomps_delivered_series: jormp_jomps_delivered_series,
           placement_scores: placement_scores,
           days: days,
           timezone: "America/New_York",
           view_screen: view_screen,
           current_turn: current_turn,
           round_info: round_info,
           current_round: current_round,
           turn_within_round: turn_within_round
         ), layout: false}
    end
  end

  def handle_event("client_timezone", %{"timezone" => tz}, socket) do
    {:noreply, assign(socket, timezone: tz)}
  end

  def render(assigns) do
    ~H"""
    <div id="page-root" phx-hook="Timezone" class="min-h-screen bg-gray-50 text-gray-900">
      <header class="bg-white border-b border-gray-200">
        <div class="max-w-4xl mx-auto px-4 sm:px-6 py-4 flex items-center justify-between">
          <div class="flex items-center gap-3 min-w-0">
            <a href="/" class="text-sm text-gray-400 hover:text-gray-600 shrink-0 transition-colors">
              ← Games
            </a>
            <span class="text-gray-200 shrink-0">|</span>
            <div class="min-w-0">
              <p class="font-semibold text-gray-900 truncate">
                {@game.board_name || "Game #{@game_id}"}
              </p>
              <%= if @game.game_name do %>
                <p class="text-xs text-gray-400 truncate">{@game.game_name}</p>
              <% end %>
            </div>
          </div>
          <a
            href={"https://www.wargear.net/games/view/#{@game_id}"}
            target="_blank"
            class="text-xs text-gray-400 hover:text-gray-600 shrink-0 transition-colors"
          >
            wargear.net ↗
          </a>
        </div>
      </header>

      <main class="max-w-5xl mx-auto px-4 sm:px-6 py-6 sm:py-8 flex flex-col gap-6 md:flex-row md:gap-8 md:items-start">
        <%!-- Sidebar: turn order --%>
        <%= if @view_screen && Enum.any?(@view_screen.players || []) do %>
          <aside class="w-full md:w-44 md:shrink-0">
            <h2 class="text-xs font-semibold uppercase tracking-widest text-gray-400 mb-2">
              Turn Order
            </h2>

            <%!-- Mobile: horizontal scrolling chips, rotated so current player is first --%>
            <% indexed = Enum.with_index(@view_screen.players, 1) %>
            <% split_at = Enum.find_index(indexed, fn {p, _} -> p.current_turn? end) || 0 %>
            <% {before, from_current} = Enum.split(indexed, split_at) %>
            <div class="flex gap-2 overflow-x-auto pb-1 md:hidden">
              <%= for {player, idx} <- from_current ++ before do %>
                <div class={[
                  "flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs whitespace-nowrap border shrink-0",
                  cond do
                    player.current_turn? ->
                      "bg-orange-50 border-orange-200 text-orange-900 font-semibold"

                    player.eliminated? ->
                      "border-gray-100 text-gray-400 line-through opacity-50"

                    true ->
                      "border-gray-200 text-gray-600"
                  end
                ]}>
                  <span class="text-gray-400 tabular-nums">{idx}</span>
                  <span>{player.name}</span>
                  <%= if player.current_turn? && @current_round && @turn_within_round do %>
                    <span class="text-orange-400">
                      {@current_round}.{@turn_within_round}
                    </span>
                  <% end %>
                  <%= if player.current_turn? do %>
                    <span class="w-1.5 h-1.5 rounded-full bg-orange-400 shrink-0"></span>
                  <% end %>
                </div>
              <% end %>
            </div>

            <%!-- Desktop: vertical list --%>
            <div class="hidden md:flex flex-col gap-1">
              <%= for {player, idx} <- Enum.with_index(@view_screen.players, 1) do %>
                <div class={[
                  "flex items-center gap-2 px-3 py-2 rounded-lg text-sm",
                  cond do
                    player.current_turn? -> "bg-orange-50 border border-orange-200"
                    player.eliminated? -> "opacity-40"
                    true -> ""
                  end
                ]}>
                  <span class="text-xs text-gray-400 tabular-nums w-4 shrink-0">{idx}</span>
                  <div class="flex-1 min-w-0">
                    <span class={[
                      "block truncate",
                      if(player.current_turn?,
                        do: "font-semibold text-orange-900",
                        else: "text-gray-700"
                      ),
                      if(player.eliminated?, do: "line-through", else: "")
                    ]}>
                      {player.name}
                    </span>
                    <%= if player.current_turn? && @current_round && @turn_within_round do %>
                      <span class="text-xs text-orange-600 font-medium">
                        Turn {@current_round}.{@turn_within_round}
                      </span>
                    <% end %>
                    <%= if player.current_turn? && @current_turn && @current_turn.started_at do %>
                      <span class="text-xs text-orange-400">
                        {elapsed(@current_turn.started_at)}
                      </span>
                    <% end %>
                  </div>
                  <%= if player.eliminated? do %>
                    <span class="text-gray-400 shrink-0">✕</span>
                  <% end %>
                  <%= if player.current_turn? do %>
                    <span class="w-1.5 h-1.5 rounded-full bg-orange-400 shrink-0"></span>
                  <% end %>
                </div>
              <% end %>
            </div>
          </aside>
        <% end %>

        <%!-- Main content --%>
        <div class="flex-1 flex flex-col gap-6 sm:gap-8 min-w-0">
          <%!-- Winner banner --%>
          <%= if @game.finished && Enum.any?(@game.winners) do %>
            <div class="bg-amber-50 border border-amber-200 rounded-xl px-6 py-5 flex items-center gap-4">
              <span class="text-3xl">🏆</span>
              <div>
                <p class="text-xs font-semibold uppercase tracking-widest text-amber-500 mb-0.5">
                  Winner
                </p>
                <p class="text-xl font-bold text-amber-700">
                  {Enum.join(@game.winners, " & ")}
                </p>
              </div>
            </div>
          <% end %>

          <%!-- Game stats row --%>
          <section class="bg-white border border-gray-200 rounded-xl shadow-sm px-6 py-5">
            <div class="flex items-center justify-between mb-4">
              <h2 class="text-xs font-semibold uppercase tracking-widest text-gray-400">
                Game Summary
              </h2>
              <%= if @game.created do %>
                <span class="text-xs text-gray-400">{format_game_date(@game.created)}</span>
              <% end %>
            </div>
            <dl class="grid grid-cols-2 sm:grid-cols-3 gap-x-8 gap-y-4 text-sm">
              <%= if @current_turn do %>
                <div>
                  <dt class="text-xs text-gray-400 mb-0.5">Days</dt>
                  <dd class="font-semibold text-gray-900 tabular-nums">
                    {game_day(@game.created)}
                  </dd>
                </div>
                <div>
                  <dt class="text-xs text-gray-400 mb-0.5">Round</dt>
                  <dd class="font-semibold text-gray-900 tabular-nums">{@current_round}</dd>
                </div>
                <div>
                  <dt class="text-xs text-gray-400 mb-0.5">Turn</dt>
                  <dd class="font-semibold text-gray-900 tabular-nums">{@turn_within_round}</dd>
                </div>
              <% end %>
              <div>
                <dt class="text-xs text-gray-400 mb-0.5">Total turns</dt>
                <dd class="font-semibold text-gray-900 tabular-nums">
                  {@log_summary.turn_count}
                </dd>
              </div>
              <div>
                <dt class="text-xs text-gray-400 mb-0.5">Log Events</dt>
                <dd class="font-semibold text-gray-900 tabular-nums">{@log_summary.max_seq}</dd>
              </div>
              <%= if @days do %>
                <div>
                  <dt class="text-xs text-gray-400 mb-0.5">Duration</dt>
                  <dd class="font-semibold text-gray-900 tabular-nums">{@days} days</dd>
                </div>
              <% end %>
              <%= if @game.finished do %>
                <div>
                  <dt class="text-xs text-gray-400 mb-0.5">Finished</dt>
                  <dd class="text-gray-700">{format_game_date(@game.finished)}</dd>
                </div>
              <% end %>
            </dl>
          </section>

          <%!-- Net Units Chart --%>
          <%= if map_size(@net_units_series) > 0 do %>
            <section>
              <div class="flex items-center justify-between mb-1">
                <h2 class="text-xs font-semibold uppercase tracking-widest text-gray-400">
                  Net Units Over Time
                </h2>
                <button
                  phx-click={JS.dispatch("reset-zoom", to: "#net-units-chart")}
                  class="text-xs text-gray-400 hover:text-gray-600 transition-colors"
                >
                  Reset Zoom
                </button>
              </div>
              <p class="text-xs text-gray-400 mb-3">
                Each player's unit count after gains and losses — drag to zoom, double-click to reset.
              </p>
              <div class="bg-white border border-gray-200 rounded-xl shadow-sm p-4 relative h-[260px] sm:h-[420px]">
                <canvas
                  id="net-units-chart"
                  phx-hook="NetUnitsChart"
                  data-series={Jason.encode!(@net_units_series)}
                  data-colors={Jason.encode!(@game.player_colors || %{})}
                  data-order={
                    Jason.encode!(
                      if @view_screen, do: Enum.map(@view_screen.players, & &1.name), else: []
                    )
                  }
                >
                </canvas>
              </div>

              <%!-- Placement scores --%>
              <%= if map_size(@placement_scores) > 0 do %>
                <div class="mt-4 bg-white border border-gray-200 rounded-xl shadow-sm divide-y divide-gray-100">
                  <div class="px-5 py-3">
                    <h3 class="text-xs font-semibold uppercase tracking-widest text-gray-400">
                      Leaderboard
                    </h3>
                    <p class="text-xs text-gray-400 mt-0.5">
                      Area under the units curve — higher = more units held longer.
                    </p>
                  </div>
                  <%= for {{player, score}, rank} <-
                      @placement_scores
                      |> Enum.sort_by(&elem(&1, 1), :desc)
                      |> Enum.with_index(1) do %>
                    <div class="flex items-center gap-3 px-5 py-2.5">
                      <span class="text-xs text-gray-300 w-6 tabular-nums shrink-0">#{rank}</span>
                      <span class="flex-1 text-sm font-medium text-gray-800">{player}</span>
                      <span class="text-sm font-mono tabular-nums text-gray-500">
                        {format_score(score)}
                      </span>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </section>
          <% end %>

          <%!-- Units Received Chart --%>
          <%= if map_size(@units_received_series) > 0 do %>
            <section>
              <div class="flex items-center justify-between mb-1">
                <h2 class="text-xs font-semibold uppercase tracking-widest text-gray-400">
                  Units Received Over Time
                </h2>
                <button
                  phx-click={JS.dispatch("reset-zoom", to: "#units-received-chart")}
                  class="text-xs text-gray-400 hover:text-gray-600 transition-colors"
                >
                  Reset Zoom
                </button>
              </div>
              <p class="text-xs text-gray-400 mb-3">Drag to zoom, double-click to reset.</p>
              <div class="bg-white border border-gray-200 rounded-xl shadow-sm p-4 relative h-[260px] sm:h-[420px]">
                <canvas
                  id="units-received-chart"
                  phx-hook="NetUnitsChart"
                  data-series={Jason.encode!(@units_received_series)}
                  data-colors={Jason.encode!(@game.player_colors || %{})}
                  data-order={
                    Jason.encode!(
                      if @view_screen, do: Enum.map(@view_screen.players, & &1.name), else: []
                    )
                  }
                >
                </canvas>
              </div>
            </section>
          <% end %>

          <%!-- Units Killed Chart --%>
          <%= if map_size(@units_killed_series) > 0 do %>
            <section>
              <div class="flex items-center justify-between mb-1">
                <h2 class="text-xs font-semibold uppercase tracking-widest text-gray-400">
                  Units Killed Over Time
                </h2>
                <button
                  phx-click={JS.dispatch("reset-zoom", to: "#units-killed-chart")}
                  class="text-xs text-gray-400 hover:text-gray-600 transition-colors"
                >
                  Reset Zoom
                </button>
              </div>
              <p class="text-xs text-gray-400 mb-3">Drag to zoom, double-click to reset.</p>
              <div class="bg-white border border-gray-200 rounded-xl shadow-sm p-4 relative h-[260px] sm:h-[420px]">
                <canvas
                  id="units-killed-chart"
                  phx-hook="NetUnitsChart"
                  data-series={Jason.encode!(@units_killed_series)}
                  data-colors={Jason.encode!(@game.player_colors || %{})}
                  data-order={
                    Jason.encode!(
                      if @view_screen, do: Enum.map(@view_screen.players, & &1.name), else: []
                    )
                  }
                >
                </canvas>
              </div>
            </section>
          <% end %>

          <%!-- Luck Ratio Chart --%>
          <%= if map_size(@luck_ratio_series) > 0 do %>
            <section>
              <div class="flex items-center justify-between mb-1">
                <h2 class="text-xs font-semibold uppercase tracking-widest text-gray-400">
                  Luck Ratio Over Time
                </h2>
                <button
                  phx-click={JS.dispatch("reset-zoom", to: "#luck-ratio-chart")}
                  class="text-xs text-gray-400 hover:text-gray-600 transition-colors"
                >
                  Reset Zoom
                </button>
              </div>
              <p class="text-xs text-gray-400 mb-3">
                Cumulative (defender losses − attacker losses) per attacker. Positive = lucky, negative = unlucky. Drag to zoom, double-click to reset.
              </p>
              <div class="bg-white border border-gray-200 rounded-xl shadow-sm p-4 relative h-[260px] sm:h-[420px]">
                <canvas
                  id="luck-ratio-chart"
                  phx-hook="NetUnitsChart"
                  data-series={Jason.encode!(@luck_ratio_series)}
                  data-colors={Jason.encode!(@game.player_colors || %{})}
                  data-order={
                    Jason.encode!(
                      if @view_screen, do: Enum.map(@view_screen.players, & &1.name), else: []
                    )
                  }
                >
                </canvas>
              </div>
            </section>
          <% end %>

          <%!-- Attacks Received Chart --%>
          <%= if map_size(@attacks_received_series) > 0 do %>
            <section>
              <div class="flex items-center justify-between mb-1">
                <h2 class="text-xs font-semibold uppercase tracking-widest text-gray-400">
                  Attacks Received Over Time
                </h2>
                <button
                  phx-click={JS.dispatch("reset-zoom", to: "#attacks-received-chart")}
                  class="text-xs text-gray-400 hover:text-gray-600 transition-colors"
                >
                  Reset Zoom
                </button>
              </div>
              <p class="text-xs text-gray-400 mb-3">
                Cumulative attacker dice directed at each player — a proxy for attacking pressure received. Drag to zoom, double-click to reset.
              </p>
              <div class="bg-white border border-gray-200 rounded-xl shadow-sm p-4 relative h-[260px] sm:h-[420px]">
                <canvas
                  id="attacks-received-chart"
                  phx-hook="NetUnitsChart"
                  data-series={Jason.encode!(@attacks_received_series)}
                  data-colors={Jason.encode!(@game.player_colors || %{})}
                  data-order={
                    Jason.encode!(
                      if @view_screen, do: Enum.map(@view_screen.players, & &1.name), else: []
                    )
                  }
                >
                </canvas>
              </div>
            </section>
          <% end %>

          <%!-- Jormp Jomps Received Chart --%>
          <%= if map_size(@jormp_jomps_received_series) > 0 do %>
            <section>
              <div class="flex items-center justify-between mb-1">
                <h2 class="text-xs font-semibold uppercase tracking-widest text-gray-400">
                  Cumulative Jormp Jomps Received
                </h2>
                <button
                  phx-click={JS.dispatch("reset-zoom", to: "#jormp-jomps-received-chart")}
                  class="text-xs text-gray-400 hover:text-gray-600 transition-colors"
                >
                  Reset Zoom
                </button>
              </div>
              <p class="text-xs text-gray-400 mb-3">
                3-dice attack → 2 attacker losses, 0 defender losses. The attacker got jormp jomped.
              </p>
              <div class="bg-white border border-gray-200 rounded-xl shadow-sm p-4 relative h-[260px] sm:h-[420px]">
                <canvas
                  id="jormp-jomps-received-chart"
                  phx-hook="NetUnitsChart"
                  data-series={Jason.encode!(@jormp_jomps_received_series)}
                  data-colors={Jason.encode!(@game.player_colors || %{})}
                  data-order={
                    Jason.encode!(
                      if @view_screen, do: Enum.map(@view_screen.players, & &1.name), else: []
                    )
                  }
                >
                </canvas>
              </div>
            </section>
          <% end %>

          <%!-- Jormp Jomps Delivered Chart --%>
          <%= if map_size(@jormp_jomps_delivered_series) > 0 do %>
            <section>
              <div class="flex items-center justify-between mb-1">
                <h2 class="text-xs font-semibold uppercase tracking-widest text-gray-400">
                  Cumulative Jormp Jomps Delivered
                </h2>
                <button
                  phx-click={JS.dispatch("reset-zoom", to: "#jormp-jomps-delivered-chart")}
                  class="text-xs text-gray-400 hover:text-gray-600 transition-colors"
                >
                  Reset Zoom
                </button>
              </div>
              <p class="text-xs text-gray-400 mb-3">
                Times this player's defense caused 2 attacker losses with 0 defender losses on a 3-dice attack.
              </p>
              <div class="bg-white border border-gray-200 rounded-xl shadow-sm p-4 relative h-[260px] sm:h-[420px]">
                <canvas
                  id="jormp-jomps-delivered-chart"
                  phx-hook="NetUnitsChart"
                  data-series={Jason.encode!(@jormp_jomps_delivered_series)}
                  data-colors={Jason.encode!(@game.player_colors || %{})}
                  data-order={
                    Jason.encode!(
                      if @view_screen, do: Enum.map(@view_screen.players, & &1.name), else: []
                    )
                  }
                >
                </canvas>
              </div>
            </section>
          <% end %>
        </div>
      </main>
    </div>
    """
  end

  # --- Private ---

  defp game_duration_days(%{created: nil}), do: nil
  defp game_duration_days(%{finished: nil}), do: nil

  defp game_duration_days(%{created: created, finished: finished}) do
    with %NaiveDateTime{} = start_dt <- Games.parse_game_date(created),
         %NaiveDateTime{} = end_dt <- Games.parse_game_date(finished) do
      NaiveDateTime.diff(end_dt, start_dt, :day)
    else
      _ -> nil
    end
  end

  defp game_day(nil), do: nil

  defp game_day(created_str) do
    case Games.parse_game_date(created_str) do
      %NaiveDateTime{} = ndt ->
        start = DateTime.from_naive!(ndt, "Etc/UTC")
        div(DateTime.diff(DateTime.utc_now(), start, :second), 86_400) + 1

      _ ->
        nil
    end
  end

  defp format_game_date(nil), do: nil

  defp format_game_date(date_str) do
    case Games.parse_game_date(date_str) do
      %NaiveDateTime{} = ndt -> Calendar.strftime(ndt, "%b %d, %Y")
      _ -> date_str
    end
  end

  defp elapsed(started_at) do
    seconds = DateTime.diff(DateTime.utc_now(), started_at)
    h = div(seconds, 3600)
    m = div(rem(seconds, 3600), 60)

    cond do
      h > 0 and m > 0 -> "#{h}h #{m}m"
      h > 0 -> "#{h}h"
      true -> "#{m}m"
    end
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
end
