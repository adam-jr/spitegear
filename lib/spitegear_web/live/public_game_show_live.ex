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
        net_units_series = Stats.net_units_over_time(game_id)
        placement_scores = Stats.placement_scores(game_id)
        days = game_duration_days(game)
        view_screen = ViewScreens.get_latest(game_id)
        current_turn = Turns.get_open_turn(game_id)

        {:ok,
         assign(socket,
           game_id: game_id,
           game: game,
           log_summary: log_summary,
           net_units_series: net_units_series,
           placement_scores: placement_scores,
           days: days,
           timezone: "America/New_York",
           view_screen: view_screen,
           current_turn: current_turn
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
        <div class="max-w-4xl mx-auto px-6 py-4 flex items-center justify-between">
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

      <main class="max-w-5xl mx-auto px-6 py-8 flex gap-8 items-start">
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
                  active -> "bg-orange-50 border border-orange-200"
                  eliminated -> "opacity-40"
                  true -> ""
                end
              ]}>
                <span class="text-xs text-gray-400 tabular-nums w-4 shrink-0">{idx}</span>
                <div class="flex-1 min-w-0">
                  <span class={[
                    "block truncate",
                    if(active, do: "font-semibold text-orange-900", else: "text-gray-700"),
                    if(eliminated, do: "line-through", else: "")
                  ]}>
                    {name}
                  </span>
                  <%= if active && @current_turn && @current_turn.started_at do %>
                    <span class="text-xs text-orange-400">{elapsed(@current_turn.started_at)}</span>
                  <% end %>
                </div>
                <%= if eliminated do %>
                  <span class="text-gray-400 shrink-0">✕</span>
                <% end %>
                <%= if active do %>
                  <span class="w-1.5 h-1.5 rounded-full bg-orange-400 shrink-0"></span>
                <% end %>
              </div>
            <% end %>
          </aside>
        <% end %>

        <%!-- Main content --%>
        <div class="flex-1 flex flex-col gap-8 min-w-0">
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
            <h2 class="text-xs font-semibold uppercase tracking-widest text-gray-400 mb-4">
              Game Summary
            </h2>
            <dl class="grid grid-cols-2 sm:grid-cols-3 gap-x-8 gap-y-4 text-sm">
              <div>
                <dt class="text-xs text-gray-400 mb-0.5">Turns (log)</dt>
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
              <%= if @game.created do %>
                <div>
                  <dt class="text-xs text-gray-400 mb-0.5">Started</dt>
                  <dd class="text-gray-700">{format_wargear_date(@game.created, @timezone)}</dd>
                </div>
              <% end %>
              <%= if @game.finished do %>
                <div>
                  <dt class="text-xs text-gray-400 mb-0.5">Finished</dt>
                  <dd class="text-gray-700">{format_wargear_date(@game.finished, @timezone)}</dd>
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
              <div class="bg-white border border-gray-200 rounded-xl shadow-sm p-4 relative h-[420px]">
                <canvas
                  id="net-units-chart"
                  phx-hook="NetUnitsChart"
                  data-series={Jason.encode!(@net_units_series)}
                  data-colors={Jason.encode!(@game.player_colors || %{})}
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

  defp format_wargear_date(nil, _tz), do: nil

  defp format_wargear_date(date_str, tz) do
    with %NaiveDateTime{} = ndt <- Games.parse_game_date(date_str),
         {:ok, et_dt} <- DateTime.from_naive(ndt, "America/New_York"),
         {:ok, local} <- DateTime.shift_zone(et_dt, tz) do
      Calendar.strftime(local, "%b %d, %Y %I:%M %p") <> " #{local.zone_abbr}"
    else
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
