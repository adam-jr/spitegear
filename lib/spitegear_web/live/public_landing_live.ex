defmodule SpitegearWeb.PublicLandingLive do
  use SpitegearWeb, :live_view
  alias Spitegear.Games

  def mount(_params, _session, socket) do
    active_games =
      Games.list_active_games()
      |> Enum.map(fn game ->
        turn = Games.get_current_turn(game.game_id)
        statuses = Games.list_player_statuses(game.game_id)
        alive = Enum.filter(statuses, & &1.alive)
        %{game: game, current_turn: turn, alive_players: alive}
      end)

    finished_games = Games.list_finished_games()

    {:ok,
     assign(socket,
       all_active: active_games,
       all_finished: finished_games,
       active_games: active_games,
       finished_games: Enum.take(finished_games, 10),
       query: ""
     ), layout: false}
  end

  def handle_event("search", %{"query" => q}, socket) do
    q_down = String.downcase(q)

    active =
      if q_down == "" do
        socket.assigns.all_active
      else
        Enum.filter(socket.assigns.all_active, fn %{game: g} ->
          String.contains?(String.downcase(g.game_name || g.game_id), q_down)
        end)
      end

    finished =
      if q_down == "" do
        Enum.take(socket.assigns.all_finished, 10)
      else
        socket.assigns.all_finished
        |> Enum.filter(fn g ->
          String.contains?(String.downcase(g.game_name || g.game_id), q_down)
        end)
        |> Enum.take(20)
      end

    {:noreply, assign(socket, query: q, active_games: active, finished_games: finished)}
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 text-gray-900">
      <header class="bg-white border-b border-gray-200">
        <div class="max-w-4xl mx-auto px-6 py-4 flex items-center justify-between">
          <div>
            <h1 class="text-lg font-bold tracking-tight">⚔️ Spitegear</h1>
            <p class="text-xs text-gray-400 mt-0.5">Wargear.net game tracker</p>
          </div>
          <a
            href="https://www.wargear.net"
            target="_blank"
            class="text-xs text-gray-400 hover:text-gray-600 transition-colors"
          >
            wargear.net ↗
          </a>
        </div>
      </header>

      <main class="max-w-4xl mx-auto px-6 py-8 flex flex-col gap-10">
        <div>
          <input
            type="text"
            name="query"
            value={@query}
            placeholder="Search games…"
            phx-change="search"
            autocomplete="off"
            class="w-full max-w-sm px-4 py-2 text-sm bg-white border border-gray-200 rounded-lg shadow-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
          />
        </div>

        <%!-- Active Games --%>
        <section>
          <h2 class="text-xs font-semibold uppercase tracking-widest text-gray-400 mb-4">
            Active Games
          </h2>
          <%= if Enum.empty?(@active_games) do %>
            <p class="text-sm text-gray-400">
              <%= if @query == "", do: "No active games right now.", else: "No active games match your search." %>
            </p>
          <% else %>
            <div class="grid gap-4 sm:grid-cols-2">
              <%= for %{game: game, current_turn: turn, alive_players: alive} <- @active_games do %>
                <a href={"/games/#{game.game_id}"} class="block group">
                  <div class="bg-white border border-gray-200 rounded-xl p-5 shadow-sm flex flex-col gap-3 group-hover:border-gray-300 group-hover:shadow transition-all">
                    <div class="flex items-start justify-between gap-2">
                      <div class="min-w-0">
                        <p class="font-semibold text-gray-900 truncate">
                          <%= game.game_name || "Game #{game.game_id}" %>
                        </p>
                        <%= if game.board_name do %>
                          <p class="text-xs text-gray-400 mt-0.5 truncate"><%= game.board_name %></p>
                        <% end %>
                      </div>
                      <span class="text-xs text-gray-300 group-hover:text-gray-400 shrink-0 mt-0.5 transition-colors">
                        →
                      </span>
                    </div>

                    <div class="text-sm">
                      <%= if turn do %>
                        <div class="flex items-center gap-2">
                          <span class="inline-block w-2 h-2 rounded-full bg-green-400 shrink-0"></span>
                          <span class="font-medium text-gray-800"><%= turn.player_name %></span>
                          <span class="text-gray-300">·</span>
                          <span class="text-gray-400 text-xs"><%= elapsed(turn.started) %></span>
                        </div>
                      <% else %>
                        <span class="text-gray-300 text-xs">No active turn</span>
                      <% end %>
                    </div>

                    <%= if Enum.any?(alive) do %>
                      <div class="flex flex-wrap gap-1.5">
                        <%= for p <- alive do %>
                          <span class="text-xs bg-gray-100 text-gray-600 px-2.5 py-0.5 rounded-full">
                            <%= p.player_name %>
                          </span>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                </a>
              <% end %>
            </div>
          <% end %>
        </section>

        <%!-- Recent Results --%>
        <%= if Enum.any?(@finished_games) do %>
          <section>
            <h2 class="text-xs font-semibold uppercase tracking-widest text-gray-400 mb-4">
              <%= if @query == "", do: "Recent Results", else: "Results" %>
            </h2>
            <div class="bg-white border border-gray-200 rounded-xl shadow-sm divide-y divide-gray-100">
              <%= for game <- @finished_games do %>
                <a href={"/games/#{game.game_id}"} class="flex items-start justify-between gap-4 px-5 py-3.5 hover:bg-gray-50 transition-colors group">
                  <div class="min-w-0">
                    <p class="text-sm font-medium text-gray-900 truncate group-hover:text-blue-600 transition-colors">
                      <%= game.game_name || "Game #{game.game_id}" %>
                    </p>
                    <%= if game.board_name do %>
                      <p class="text-xs text-gray-400 mt-0.5"><%= game.board_name %></p>
                    <% end %>
                  </div>
                  <div class="text-right shrink-0">
                    <%= if Enum.any?(game.winners) do %>
                      <p class="text-sm font-medium text-amber-600">
                        🏆 <%= Enum.join(game.winners, ", ") %>
                      </p>
                    <% end %>
                    <%= if game.finished do %>
                      <p class="text-xs text-gray-400 mt-0.5"><%= game.finished %></p>
                    <% end %>
                  </div>
                </a>
              <% end %>
            </div>
          </section>
        <% end %>
      </main>
    </div>
    """
  end

  defp elapsed(nil), do: "—"

  defp elapsed(started) do
    started
    |> DateTime.diff(DateTime.utc_now())
    |> abs()
    |> format_duration()
  end

  defp format_duration(s) when s < 60, do: "#{s}s"
  defp format_duration(s) when s < 3600, do: "#{div(s, 60)}m"

  defp format_duration(s) do
    h = div(s, 3600)
    m = div(rem(s, 3600), 60)
    if m > 0, do: "#{h}h #{m}m", else: "#{h}h"
  end
end
