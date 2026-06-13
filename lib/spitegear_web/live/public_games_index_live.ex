defmodule SpitegearWeb.PublicGamesIndexLive do
  use SpitegearWeb, :live_view
  alias Spitegear.Games
  alias Spitegear.LiveGameState.Turns

  def mount(_params, _session, socket) do
    active_games =
      Games.list_active_games()
      |> Enum.map(fn game ->
        turn = Turns.get_open_turn(game.game_id)
        %{game: game, current_turn: turn}
      end)

    finished_games = Games.list_finished_games()
    all_games = active_games ++ Enum.map(finished_games, &%{game: &1, current_turn: nil})

    {:ok,
     assign(socket,
       all_games: all_games,
       filtered: all_games,
       query: ""
     ), layout: false}
  end

  def handle_event("search", %{"query" => q}, socket) do
    q_down = String.downcase(q)

    filtered =
      if q_down == "" do
        socket.assigns.all_games
      else
        Enum.filter(socket.assigns.all_games, fn %{game: g} ->
          String.contains?(String.downcase(g.board_name || ""), q_down) ||
            String.contains?(String.downcase(g.game_name || ""), q_down) ||
            String.contains?(String.downcase(Enum.join(g.winners || [], " ")), q_down)
        end)
      end

    {:noreply, assign(socket, query: q, filtered: filtered)}
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 text-gray-900">
      <header class="bg-white border-b border-gray-200">
        <div class="max-w-4xl mx-auto px-6 py-4 flex items-center justify-between">
          <div class="flex items-center gap-3">
            <a href="/" class="text-sm text-gray-400 hover:text-gray-600 transition-colors">
              ← Home
            </a>
            <span class="text-gray-200">|</span>
            <h1 class="text-lg font-bold tracking-tight">All Games</h1>
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

      <main class="max-w-4xl mx-auto px-6 py-8 flex flex-col gap-6">
        <input
          type="text"
          name="query"
          value={@query}
          placeholder="Search by board, title, or winner…"
          phx-change="search"
          autocomplete="off"
          class="w-full max-w-sm px-4 py-2 text-sm bg-white border border-gray-200 rounded-lg shadow-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
        />

        <%= if Enum.empty?(@filtered) do %>
          <p class="text-sm text-gray-400">No games match your search.</p>
        <% else %>
          <div class="bg-white border border-gray-200 rounded-xl shadow-sm divide-y divide-gray-100">
            <%= for %{game: game, current_turn: turn} <- @filtered do %>
              <a
                href={"/games/#{game.game_id}"}
                class="flex items-center gap-4 px-5 py-3.5 hover:bg-gray-50 transition-colors group"
              >
                <%!-- Status dot --%>
                <span class={[
                  "w-2 h-2 rounded-full shrink-0",
                  if(is_nil(game.finished), do: "bg-green-400", else: "bg-gray-200")
                ]}>
                </span>

                <%!-- Game info --%>
                <div class="flex-1 min-w-0">
                  <p class="text-sm font-medium text-gray-900 group-hover:text-blue-600 transition-colors truncate">
                    {game.board_name || "Game #{game.game_id}"}
                  </p>
                  <%= if game.game_name do %>
                    <p class="text-xs text-gray-400 truncate">{game.game_name}</p>
                  <% end %>
                </div>

                <%!-- Active: current player / Finished: winner --%>
                <div class="text-right shrink-0">
                  <%= if is_nil(game.finished) do %>
                    <%= if turn do %>
                      <p class="text-xs text-gray-600 font-medium">{turn.player_name}</p>
                      <p class="text-xs text-gray-400">active turn</p>
                    <% else %>
                      <p class="text-xs text-gray-400">active</p>
                    <% end %>
                  <% else %>
                    <%= if Enum.any?(game.winners) do %>
                      <p class="text-xs font-medium text-amber-600">
                        🏆 {Enum.join(game.winners, ", ")}
                      </p>
                    <% end %>
                    <%= if game.finished do %>
                      <p class="text-xs text-gray-400 mt-0.5">{game.finished}</p>
                    <% end %>
                  <% end %>
                </div>
              </a>
            <% end %>
          </div>
        <% end %>
      </main>
    </div>
    """
  end
end
