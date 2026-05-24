defmodule SpitegearWeb.PublicLandingLive do
  use SpitegearWeb, :live_view
  alias Spitegear.Games

  def mount(_params, _session, socket) do
    active_games =
      Games.list_active_games()
      |> Enum.map(fn game ->
        turn = Games.get_current_turn(game.game_id)
        %{game: game, current_turn: turn}
      end)

    finished_games = Games.list_finished_games()
    leaderboard = Games.leaderboard()
    most_recent = List.first(finished_games)

    {:ok,
     assign(socket,
       active_games: active_games,
       recent_games: Enum.take(finished_games, 8),
       most_recent: most_recent,
       leaderboard: leaderboard
     ), layout: false}
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 text-gray-900">
      <header class="bg-white border-b border-gray-200">
        <div class="max-w-6xl mx-auto px-6 py-4 flex items-center justify-between">
          <h1 class="text-lg font-bold tracking-tight">⚔️ Spitegear</h1>
          <a
            href="https://www.wargear.net"
            target="_blank"
            class="text-xs text-gray-400 hover:text-gray-600 transition-colors"
          >
            wargear.net ↗
          </a>
        </div>
      </header>

      <div class="max-w-6xl mx-auto px-6 py-8 flex gap-8 items-start">
        <%!-- Sidebar --%>
        <aside class="w-64 shrink-0 flex flex-col gap-6">
          <%!-- Active games --%>
          <%= if Enum.any?(@active_games) do %>
            <section>
              <h2 class="text-xs font-semibold uppercase tracking-widest text-gray-400 mb-3">
                Active
              </h2>
              <div class="flex flex-col gap-2">
                <%= for %{game: game, current_turn: turn} <- @active_games do %>
                  <a
                    href={"/games/#{game.game_id}"}
                    class="bg-white border border-gray-200 rounded-lg px-3 py-2.5 hover:border-gray-300 hover:shadow-sm transition-all group"
                  >
                    <p class="text-sm font-medium text-gray-900 truncate group-hover:text-blue-600 transition-colors">
                      <%= game.board_name || "Game #{game.game_id}" %>
                    </p>
                    <%= if game.game_name do %>
                      <p class="text-xs text-gray-400 truncate mt-0.5"><%= game.game_name %></p>
                    <% end %>
                    <%= if turn do %>
                      <div class="flex items-center gap-1.5 mt-1.5">
                        <span class="w-1.5 h-1.5 rounded-full bg-green-400 shrink-0"></span>
                        <span class="text-xs text-gray-500 truncate"><%= turn.player_name %></span>
                      </div>
                    <% end %>
                  </a>
                <% end %>
              </div>
            </section>
          <% end %>

          <%!-- Recent results --%>
          <%= if Enum.any?(@recent_games) do %>
            <section>
              <h2 class="text-xs font-semibold uppercase tracking-widest text-gray-400 mb-3">
                Recent
              </h2>
              <div class="flex flex-col gap-1">
                <%= for game <- @recent_games do %>
                  <a
                    href={"/games/#{game.game_id}"}
                    class="flex flex-col px-3 py-2 rounded-lg hover:bg-white hover:shadow-sm transition-all group"
                  >
                    <p class="text-sm font-medium text-gray-700 truncate group-hover:text-blue-600 transition-colors">
                      <%= game.board_name || "Game #{game.game_id}" %>
                    </p>
                    <%= if game.game_name do %>
                      <p class="text-xs text-gray-400 truncate"><%= game.game_name %></p>
                    <% end %>
                    <%= if Enum.any?(game.winners) do %>
                      <p class="text-xs text-amber-600 mt-0.5 truncate">
                        🏆 <%= Enum.join(game.winners, ", ") %>
                      </p>
                    <% end %>
                  </a>
                <% end %>
              </div>
              <a
                href="/games"
                class="inline-block mt-3 text-xs text-gray-400 hover:text-gray-600 transition-colors"
              >
                All games →
              </a>
            </section>
          <% end %>
        </aside>

        <%!-- Main content --%>
        <div class="flex-1 flex flex-col gap-8 min-w-0">
          <%!-- Most recent result --%>
          <%= if @most_recent do %>
            <section>
              <h2 class="text-xs font-semibold uppercase tracking-widest text-gray-400 mb-3">
                Most Recent Result
              </h2>
              <a href={"/games/#{@most_recent.game_id}"} class="block group">
                <div class="bg-white border border-gray-200 rounded-xl shadow-sm p-6 hover:border-gray-300 hover:shadow transition-all">
                  <div class="flex items-start justify-between gap-4">
                    <div class="min-w-0">
                      <p class="text-xl font-bold text-gray-900 group-hover:text-blue-600 transition-colors truncate">
                        <%= @most_recent.board_name || "Game #{@most_recent.game_id}" %>
                      </p>
                      <%= if @most_recent.game_name do %>
                        <p class="text-sm text-gray-400 mt-0.5 truncate"><%= @most_recent.game_name %></p>
                      <% end %>
                    </div>
                    <span class="text-gray-300 group-hover:text-gray-500 shrink-0 transition-colors">
                      →
                    </span>
                  </div>
                  <%= if Enum.any?(@most_recent.winners) do %>
                    <div class="mt-4 flex items-center gap-2">
                      <span class="text-2xl">🏆</span>
                      <span class="text-lg font-semibold text-amber-600">
                        <%= Enum.join(@most_recent.winners, " & ") %>
                      </span>
                    </div>
                  <% end %>
                  <%= if @most_recent.finished do %>
                    <p class="text-xs text-gray-400 mt-3"><%= @most_recent.finished %></p>
                  <% end %>
                </div>
              </a>
            </section>
          <% end %>

          <%!-- Leaderboard --%>
          <%= if Enum.any?(@leaderboard) do %>
            <section>
              <h2 class="text-xs font-semibold uppercase tracking-widest text-gray-400 mb-3">
                All-Time Leaderboard
              </h2>
              <div class="bg-white border border-gray-200 rounded-xl shadow-sm divide-y divide-gray-100">
                <%= for {{player, wins}, rank} <- Enum.with_index(@leaderboard, 1) do %>
                  <div class="flex items-center gap-3 px-5 py-3">
                    <span class={[
                      "w-7 text-center text-sm font-bold shrink-0",
                      case rank do
                        1 -> "text-amber-500"
                        2 -> "text-gray-400"
                        3 -> "text-amber-700"
                        _ -> "text-gray-300"
                      end
                    ]}>
                      <%= rank %>
                    </span>
                    <span class="flex-1 text-sm font-medium text-gray-800"><%= player %></span>
                    <span class="text-sm tabular-nums text-gray-500">
                      <%= wins %> <%= if wins == 1, do: "win", else: "wins" %>
                    </span>
                  </div>
                <% end %>
              </div>
            </section>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
