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
        has_map_image = Spitegear.GameMaps.get(game_id) != nil
        log_summary = Stats.game_log_summary(game_id)
        total_board_units_series = Stats.total_board_units_series(game_id)
        net_units_series = Stats.enriched_net_units_series(game_id)
        units_received_series = Stats.units_received_series(game_id)
        units_killed_series = Stats.units_killed_series(game_id)
        luck_delta_series = Stats.luck_delta_series(game_id)
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
            {round_info.current_round, round_info.turn_number_within_round}
          else
            {nil, nil}
          end

        {:ok,
         assign(socket,
           game_id: game_id,
           game: game,
           log_summary: log_summary,
           total_board_units_series: total_board_units_series,
           net_units_series: net_units_series,
           units_received_series: units_received_series,
           units_killed_series: units_killed_series,
           luck_delta_series: luck_delta_series,
           attacks_received_series: attacks_received_series,
           jormp_jomps_received_series: jormp_jomps_received_series,
           jormp_jomps_delivered_series: jormp_jomps_delivered_series,
           placement_scores: placement_scores,
           days: days,
           has_map_image: has_map_image,
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
    <div id="page-root" phx-hook="Timezone" class="min-h-screen bg-[#0d1117] text-gray-100 flex flex-col">
      <%!-- Winner banner --%>
      <%= if @game.finished && Enum.any?(@game.winners) do %>
        <div class="bg-amber-950/60 border-b border-amber-800/40 px-6 py-4 flex items-center gap-4">
          <span class="text-2xl">🏆</span>
          <div>
            <p class="text-[10px] font-semibold uppercase tracking-widest text-amber-600 mb-0.5">
              Winner
            </p>
            <p class="text-lg font-bold text-amber-300">{Enum.join(@game.winners, " & ")}</p>
          </div>
        </div>
      <% end %>

      <%!-- Command view: left rail + map --%>
      <div class="flex flex-1 min-h-screen">
        <%!-- Left rail --%>
        <aside class="w-60 shrink-0 border-r border-gray-800 flex flex-col overflow-y-auto">
          <%!-- Nav + title --%>
          <div class="px-5 pt-5 pb-4">
            <a href="/" class="text-xs text-gray-600 hover:text-gray-400 transition-colors">
              ← Games
            </a>
            <h1 class="text-base font-bold text-white leading-snug mt-3">
              {@game.board_name || "Game #{@game_id}"}
            </h1>
            <%= if @game.game_name do %>
              <p class="text-xs text-gray-500 mt-1 leading-snug">{@game.game_name}</p>
            <% end %>
            <%= if @current_round && @turn_within_round do %>
              <p class="text-[10px] font-mono tracking-widest text-gray-600 mt-3 uppercase">
                Round {@current_round} · Day {game_day(@game.created)} · Turn {@turn_within_round}
              </p>
            <% end %>
          </div>

          <div class="mx-5 border-t border-gray-800"></div>

          <%!-- Summary stats --%>
          <div class="px-5 py-4 flex flex-col gap-2.5">
            <%= if @game.created do %>
              <div class="flex justify-between items-baseline">
                <span class="text-xs text-gray-600">Days Elapsed</span>
                <span class="text-sm font-mono text-gray-300 tabular-nums">
                  {game_day(@game.created)}
                </span>
              </div>
            <% end %>
            <div class="flex justify-between items-baseline">
              <span class="text-xs text-gray-600">Total Turns</span>
              <span class="text-sm font-mono text-gray-300 tabular-nums">
                {@log_summary.turn_count}
              </span>
            </div>
            <div class="flex justify-between items-baseline">
              <span class="text-xs text-gray-600">Log Events</span>
              <span class="text-sm font-mono text-gray-300 tabular-nums">
                {@log_summary.max_seq}
              </span>
            </div>
            <%= if @view_screen && @view_screen.players do %>
              <div class="flex justify-between items-baseline">
                <span class="text-xs text-gray-600">Players</span>
                <span class="text-sm font-mono text-gray-300 tabular-nums">
                  {length(@view_screen.players)}
                </span>
              </div>
            <% end %>
            <%= if @game.finished && @days do %>
              <div class="flex justify-between items-baseline">
                <span class="text-xs text-gray-600">Duration</span>
                <span class="text-sm font-mono text-gray-300 tabular-nums">{@days}d</span>
              </div>
            <% end %>
          </div>

          <div class="mx-5 border-t border-gray-800"></div>

          <%!-- Current turn player list --%>
          <%= if @view_screen && Enum.any?(@view_screen.players || []) do %>
            <div class="px-5 py-4 flex flex-col flex-1">
              <p class="text-[10px] font-semibold uppercase tracking-widest text-gray-600 mb-3">
                Current Turn
              </p>
              <div class="flex flex-col gap-0.5">
                <%= for {player, idx} <- Enum.with_index(@view_screen.players, 1) do %>
                  <%= if player.current_turn? do %>
                    <div class="rounded px-3 py-2.5 bg-orange-950/50 border border-orange-800/30 mb-1">
                      <div class="flex items-center gap-2">
                        <span class="text-xs text-orange-700 tabular-nums w-4 shrink-0">{idx}</span>
                        <span class="text-sm font-semibold text-orange-300 truncate">
                          {player.name}
                        </span>
                      </div>
                      <p class="text-xs text-orange-700/80 mt-0.5 ml-6">
                        <%= if @current_round && @turn_within_round do %>
                          Turn {@current_round}.{@turn_within_round}
                        <% end %>
                        <%= if @current_turn && @current_turn.started_at do %>
                          &nbsp;·&nbsp;{elapsed(@current_turn.started_at)}
                        <% end %>
                      </p>
                    </div>
                  <% else %>
                    <div class={[
                      "flex items-center gap-2 px-3 py-1 rounded",
                      if(player.eliminated?, do: "opacity-30", else: "")
                    ]}>
                      <span class="text-xs text-gray-700 tabular-nums w-4 shrink-0">{idx}</span>
                      <span class={[
                        "text-sm truncate",
                        if(player.eliminated?,
                          do: "line-through text-gray-600",
                          else: "text-gray-400"
                        )
                      ]}>
                        {player.name}
                      </span>
                    </div>
                  <% end %>
                <% end %>
              </div>
            </div>
          <% end %>
        </aside>

        <%!-- Map area --%>
        <div class="flex-1 relative flex items-center justify-center p-6 overflow-hidden">
          <a
            href={"https://www.wargear.net/games/view/#{@game_id}"}
            target="_blank"
            class="absolute top-4 right-4 text-xs text-gray-700 hover:text-gray-500 z-10 transition-colors"
          >
            wargear.net ↗
          </a>
          <%= if @has_map_image do %>
            <img
              id="game-map-img"
              src={"/games/#{@game_id}/map"}
              alt="Game map"
              phx-click={JS.toggle_class("max-h-[70vh]", to: "#game-map-img")}
              class="max-h-[70vh] max-w-full object-contain cursor-pointer transition-all duration-300"
            />
          <% else %>
            <p class="text-gray-700 text-sm">No map available</p>
          <% end %>
        </div>
      </div>

      <%!-- Charts section — below the fold --%>
      <div class="border-t border-gray-800">
        <%= if @view_screen && @view_screen.fogged? && !@game.finished do %>
          <div class="px-8 py-14 text-center">
            <p class="text-3xl mb-3">🌫️</p>
            <p class="text-sm font-medium text-gray-500">Stats hidden — game is fogged</p>
            <p class="text-xs text-gray-700 mt-1">Available after the game ends</p>
          </div>
        <% else %>
          <div class="px-8 pt-8 pb-2">
            <p class="text-[10px] font-semibold uppercase tracking-widest text-gray-600">
              Game Stats
            </p>
          </div>
          <div class="px-8 pb-16 flex flex-col gap-10">
            <%!-- Total Board Units Chart --%>
            <%= if map_size(@total_board_units_series) > 0 do %>
              <section>
                <div class="flex items-center justify-between mb-1">
                  <h2 class="text-xs font-semibold uppercase tracking-widest text-gray-500">
                    Army Strength Over Time
                  </h2>
                  <button
                    phx-click={JS.dispatch("reset-zoom", to: "#total-board-units-chart")}
                    class="text-xs text-gray-700 hover:text-gray-500 transition-colors"
                  >
                    Reset Zoom
                  </button>
                </div>
                <p class="text-xs text-gray-700 mb-3">
                  Total forces currently in play across all factions. Drag to zoom, double-click to reset.
                </p>
                <div class="bg-white border border-gray-200 rounded-lg p-2 relative h-[220px] sm:h-[300px]">
                  <canvas
                    id="total-board-units-chart"
                    phx-hook="NetUnitsChart"
                    data-series={Jason.encode!(@total_board_units_series)}
                    data-colors={Jason.encode!(%{"Total" => "#6366f1"})}
                    data-order={Jason.encode!(["Total"])}
                  >
                  </canvas>
                </div>
              </section>
            <% end %>

            <%!-- Net Units Chart --%>
            <%= if map_size(@net_units_series) > 0 do %>
              <section>
                <div class="flex items-center justify-between mb-1">
                  <h2 class="text-xs font-semibold uppercase tracking-widest text-gray-500">
                    Net Units Over Time
                  </h2>
                  <button
                    phx-click={JS.dispatch("reset-zoom", to: "#net-units-chart")}
                    class="text-xs text-gray-700 hover:text-gray-500 transition-colors"
                  >
                    Reset Zoom
                  </button>
                </div>
                <p class="text-xs text-gray-700 mb-3">
                  Each player's unit count after gains and losses. Drag to zoom, double-click to reset.
                </p>
                <div class="bg-white border border-gray-200 rounded-lg p-2 relative h-[260px] sm:h-[420px]">
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
                <%!-- Placement leaderboard --%>
                <%= if map_size(@placement_scores) > 0 do %>
                  <div class="mt-4 border border-gray-800 rounded-lg divide-y divide-gray-800">
                    <div class="px-5 py-3">
                      <h3 class="text-[10px] font-semibold uppercase tracking-widest text-gray-600">
                        Leaderboard
                      </h3>
                      <p class="text-xs text-gray-700 mt-0.5">
                        Area under the units curve — higher = more units held longer.
                      </p>
                    </div>
                    <%= for {{player, score}, rank} <-
                        @placement_scores
                        |> Enum.sort_by(&elem(&1, 1), :desc)
                        |> Enum.with_index(1) do %>
                      <div class="flex items-center gap-3 px-5 py-2.5">
                        <span class="text-xs text-gray-700 w-6 tabular-nums shrink-0">
                          #{rank}
                        </span>
                        <span class="flex-1 text-sm font-medium text-gray-300">{player}</span>
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
                  <h2 class="text-xs font-semibold uppercase tracking-widest text-gray-500">
                    Units Received Over Time
                  </h2>
                  <button
                    phx-click={JS.dispatch("reset-zoom", to: "#units-received-chart")}
                    class="text-xs text-gray-700 hover:text-gray-500 transition-colors"
                  >
                    Reset Zoom
                  </button>
                </div>
                <p class="text-xs text-gray-700 mb-3">Drag to zoom, double-click to reset.</p>
                <div class="bg-white border border-gray-200 rounded-lg p-2 relative h-[260px] sm:h-[420px]">
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
                  <h2 class="text-xs font-semibold uppercase tracking-widest text-gray-500">
                    Units Killed Over Time
                  </h2>
                  <button
                    phx-click={JS.dispatch("reset-zoom", to: "#units-killed-chart")}
                    class="text-xs text-gray-700 hover:text-gray-500 transition-colors"
                  >
                    Reset Zoom
                  </button>
                </div>
                <p class="text-xs text-gray-700 mb-3">Drag to zoom, double-click to reset.</p>
                <div class="bg-white border border-gray-200 rounded-lg p-2 relative h-[260px] sm:h-[420px]">
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

            <%!-- Luck Chart --%>
            <%= if map_size(@luck_delta_series) > 0 do %>
              <section>
                <div class="flex items-center justify-between mb-1">
                  <h2 class="text-xs font-semibold uppercase tracking-widest text-gray-500">
                    Luck Over Time
                  </h2>
                  <button
                    phx-click={JS.dispatch("reset-zoom", to: "#luck-chart")}
                    class="text-xs text-gray-700 hover:text-gray-500 transition-colors"
                  >
                    Reset Zoom
                  </button>
                </div>
                <p class="text-xs text-gray-700 mb-3">
                  Cumulative troops gained or lost due to luck vs. expected dice outcomes. Positive = luckier than average, negative = unluckier. Drag to zoom, double-click to reset.
                </p>
                <div class="bg-white border border-gray-200 rounded-lg p-2 relative h-[260px] sm:h-[420px]">
                  <canvas
                    id="luck-chart"
                    phx-hook="NetUnitsChart"
                    data-series={Jason.encode!(@luck_delta_series)}
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
                  <h2 class="text-xs font-semibold uppercase tracking-widest text-gray-500">
                    Attacks Received Over Time
                  </h2>
                  <button
                    phx-click={JS.dispatch("reset-zoom", to: "#attacks-received-chart")}
                    class="text-xs text-gray-700 hover:text-gray-500 transition-colors"
                  >
                    Reset Zoom
                  </button>
                </div>
                <p class="text-xs text-gray-700 mb-3">
                  Cumulative attacker dice directed at each player — a proxy for attacking pressure received. Drag to zoom, double-click to reset.
                </p>
                <div class="bg-white border border-gray-200 rounded-lg p-2 relative h-[260px] sm:h-[420px]">
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
                  <h2 class="text-xs font-semibold uppercase tracking-widest text-gray-500">
                    Cumulative Jormp Jomps Received
                  </h2>
                  <button
                    phx-click={JS.dispatch("reset-zoom", to: "#jormp-jomps-received-chart")}
                    class="text-xs text-gray-700 hover:text-gray-500 transition-colors"
                  >
                    Reset Zoom
                  </button>
                </div>
                <p class="text-xs text-gray-700 mb-3">
                  3-dice attack → 2 attacker losses, 0 defender losses. The attacker got jormp jomped.
                </p>
                <div class="bg-white border border-gray-200 rounded-lg p-2 relative h-[260px] sm:h-[420px]">
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
                  <h2 class="text-xs font-semibold uppercase tracking-widest text-gray-500">
                    Cumulative Jormp Jomps Delivered
                  </h2>
                  <button
                    phx-click={JS.dispatch("reset-zoom", to: "#jormp-jomps-delivered-chart")}
                    class="text-xs text-gray-700 hover:text-gray-500 transition-colors"
                  >
                    Reset Zoom
                  </button>
                </div>
                <p class="text-xs text-gray-700 mb-3">
                  Times this player's defense caused 2 attacker losses with 0 defender losses on a 3-dice attack.
                </p>
                <div class="bg-white border border-gray-200 rounded-lg p-2 relative h-[260px] sm:h-[420px]">
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
        <% end %>
      </div>
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
