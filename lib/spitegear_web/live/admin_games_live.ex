defmodule SpitegearWeb.AdminGamesLive do
  use SpitegearWeb, :live_view
  alias Spitegear.Games

  def mount(_params, _session, socket) do
    {:ok, assign(socket, games: load_games(), new_game_id: "", error: nil)}
  end

  def handle_event("add_game", %{"game_id" => game_id}, socket) do
    game_id = String.trim(game_id)

    case Games.add_game(game_id) do
      {:ok, _} ->
        {:noreply, assign(socket, games: load_games(), new_game_id: "", error: nil)}

      {:error, _} ->
        {:noreply, assign(socket, error: "Failed to add game #{game_id}")}
    end
  end

  def handle_event("start_poller", %{"game_id" => game_id}, socket) do
    Games.start_poller(game_id)
    {:noreply, assign(socket, games: load_games())}
  end

  def handle_event("stop_poller", %{"game_id" => game_id}, socket) do
    Games.stop_poller(game_id)
    {:noreply, assign(socket, games: load_games())}
  end

  defp load_games do
    Games.list_active_games()
    |> Enum.map(fn game ->
      turn = Games.get_current_turn(game.game_id)
      %{game: game, turn: turn, poller_alive: Games.poller_alive?(game.game_id)}
    end)
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto mt-16 p-6 flex flex-col gap-10">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">Games</h1>
        <a href="/admin" class="text-sm text-blue-600 hover:underline">← Settings</a>
      </div>

      <section>
        <h2 class="text-lg font-semibold mb-4">Add Game</h2>
        <form phx-submit="add_game" class="flex gap-2 items-center">
          <input
            type="text"
            name="game_id"
            value={@new_game_id}
            placeholder="Wargear Game ID"
            class="font-mono text-sm border border-gray-300 rounded p-2 w-48"
            required
          />
          <button type="submit" class="bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700 text-sm">
            Add
          </button>
          <%= if @error do %>
            <span class="text-red-600 text-sm"><%= @error %></span>
          <% end %>
        </form>
      </section>

      <section>
        <h2 class="text-lg font-semibold mb-4">Active Games</h2>
        <%= if Enum.empty?(@games) do %>
          <p class="text-gray-500 text-sm">No active games.</p>
        <% else %>
          <table class="w-full text-sm border-collapse">
            <thead>
              <tr class="text-left border-b border-gray-200">
                <th class="pb-2 pr-4">Game ID</th>
                <th class="pb-2 pr-4">Name</th>
                <th class="pb-2 pr-4">Current Player</th>
                <th class="pb-2 pr-4">Poller</th>
                <th class="pb-2">Actions</th>
              </tr>
            </thead>
            <tbody>
              <%= for %{game: game, turn: turn, poller_alive: alive} <- @games do %>
                <tr class="border-b border-gray-100 align-middle">
                  <td class="py-2 pr-4 font-mono">
                    <a href={"https://www.wargear.net/games/view/#{game.game_id}"} target="_blank" class="text-blue-600 hover:underline">
                      <%= game.game_id %>
                    </a>
                  </td>
                  <td class="py-2 pr-4"><%= game.game_name || "—" %></td>
                  <td class="py-2 pr-4"><%= if turn, do: turn.player.name, else: "—" %></td>
                  <td class="py-2 pr-4">
                    <span class={if alive, do: "text-green-600", else: "text-gray-400"}>
                      <%= if alive, do: "running", else: "stopped" %>
                    </span>
                  </td>
                  <td class="py-2 flex gap-3">
                    <%= if alive do %>
                      <button phx-click="stop_poller" phx-value-game_id={game.game_id}
                        class="text-red-600 hover:underline">
                        Stop
                      </button>
                    <% else %>
                      <button phx-click="start_poller" phx-value-game_id={game.game_id}
                        class="text-blue-600 hover:underline">
                        Start
                      </button>
                    <% end %>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        <% end %>
      </section>
    </div>
    """
  end
end
