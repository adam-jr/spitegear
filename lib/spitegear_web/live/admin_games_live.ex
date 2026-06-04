defmodule SpitegearWeb.AdminGamesLive do
  use SpitegearWeb, :live_view
  alias Spitegear.Games
  alias Spitegear.LiveGameState.Turns

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       games: load_games(),
       finished_games: Games.list_finished_games(),
       snapshot_ids: Games.game_ids_with_snapshots(),
       new_game_id: "",
       error: nil,
       hist_game_id: "",
       hist_status: nil,
       refresh_status: nil,
       refresh_done: 0,
       refresh_total: 0,
       refresh_errors: [],
       backfill_status: nil
     )}
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

  def handle_event("fetch_historical", %{"game_id" => game_id}, socket) do
    game_id = String.trim(game_id)
    start_fetch(game_id, self())
    {:noreply, assign(socket, hist_game_id: game_id, hist_status: :fetching)}
  end

  def handle_event("start_poller", %{"game_id" => game_id}, socket) do
    Games.start_poller(game_id)
    {:noreply, assign(socket, games: load_games())}
  end

  def handle_event("stop_poller", %{"game_id" => game_id}, socket) do
    Games.stop_poller(game_id)
    {:noreply, assign(socket, games: load_games())}
  end

  def handle_event("refresh_all_viewscreens", _params, socket) do
    all_games = Games.list_all_games()
    total = length(all_games)
    lv = self()

    Task.start(fn ->
      Enum.each(all_games, fn game ->
        result = Games.refresh_viewscreen(game.game_id)
        send(lv, {:refresh_progress, game.game_id, result})
        Process.sleep(500)
      end)

      send(lv, :refresh_done)
    end)

    {:noreply,
     assign(socket,
       refresh_status: :running,
       refresh_done: 0,
       refresh_total: total,
       refresh_errors: []
     )}
  end

  def handle_event("backfill_all_turns", _params, socket) do
    lv = self()
    Task.start(fn -> send(lv, {:backfill_done, Turns.backfill_all_games()}) end)
    {:noreply, assign(socket, backfill_status: :running)}
  end

  def handle_info({:refresh_progress, game_id, result}, socket) do
    errors =
      case result do
        {:ok, _} -> socket.assigns.refresh_errors
        _ -> [game_id | socket.assigns.refresh_errors]
      end

    {:noreply,
     assign(socket,
       refresh_done: socket.assigns.refresh_done + 1,
       refresh_errors: errors
     )}
  end

  def handle_info({:backfill_done, count}, socket) do
    {:noreply, assign(socket, backfill_status: {:done, count})}
  end

  def handle_info(:refresh_done, socket) do
    ok_count = socket.assigns.refresh_total - length(socket.assigns.refresh_errors)

    {:noreply,
     assign(socket,
       refresh_status: {:done, ok_count, length(socket.assigns.refresh_errors)},
       finished_games: Games.list_finished_games()
     )}
  end

  def handle_info({:historical_result, _game_id, {:ok, view_screen}}, socket) do
    {:noreply,
     assign(socket,
       hist_status: {:ok, view_screen.game_name},
       hist_game_id: "",
       finished_games: Games.list_finished_games(),
       snapshot_ids: Games.game_ids_with_snapshots()
     )}
  end

  def handle_info({:historical_result, game_id, {:error, reason}}, socket) do
    {:noreply, assign(socket, hist_status: {:error, game_id, inspect(reason)})}
  end

  defp start_fetch(game_id, lv) do
    Task.start(fn ->
      send(lv, {:historical_result, game_id, Games.fetch_historical_game(game_id)})
    end)
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
          <button
            type="submit"
            class="bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700 text-sm"
          >
            Add
          </button>
          <%= if @error do %>
            <span class="text-red-600 text-sm">{@error}</span>
          <% end %>
        </form>
      </section>

      <section>
        <h2 class="text-lg font-semibold mb-1">Fetch Historical Game Log</h2>
        <p class="text-sm text-gray-500 mb-4">
          Fetches the ViewScreen and raw log HTML for a finished game and stores both. Safe to re-run.
        </p>
        <form phx-submit="fetch_historical" class="flex gap-2 items-center">
          <input
            type="text"
            name="game_id"
            value={@hist_game_id}
            placeholder="Wargear Game ID"
            class="font-mono text-sm border border-gray-300 rounded p-2 w-48"
            required
            disabled={@hist_status == :fetching}
          />
          <button
            type="submit"
            class="bg-indigo-600 text-white px-4 py-2 rounded hover:bg-indigo-700 text-sm disabled:opacity-50"
            disabled={@hist_status == :fetching}
          >
            {if @hist_status == :fetching, do: "Fetching…", else: "Fetch"}
          </button>
          <%= case @hist_status do %>
            <% {:ok, game_name} -> %>
              <span class="text-green-600 text-sm">✓ Saved — {game_name}</span>
            <% {:error, gid, reason} -> %>
              <span class="text-red-600 text-sm">Failed for {gid}: {reason}</span>
            <% _ -> %>
          <% end %>
        </form>
      </section>

      <section>
        <h2 class="text-lg font-semibold mb-1">Refresh All Viewscreens</h2>
        <p class="text-sm text-gray-500 mb-4">
          Re-fetches the ViewScreen for every tracked game and upserts metadata (names, colors, winners). No log snapshots are touched. Runs one game at a time with a short delay between each.
        </p>
        <div class="flex items-center gap-4">
          <button
            phx-click="refresh_all_viewscreens"
            disabled={@refresh_status == :running}
            class="bg-teal-600 text-white px-4 py-2 rounded hover:bg-teal-700 text-sm disabled:opacity-50"
          >
            {if @refresh_status == :running, do: "Running…", else: "Refresh All"}
          </button>
          <%= case @refresh_status do %>
            <% :running -> %>
              <span class="text-sm text-gray-500">
                {@refresh_done} / {@refresh_total}
                <%= if Enum.any?(@refresh_errors) do %>
                  · <span class="text-red-500">{length(@refresh_errors)} failed</span>
                <% end %>
              </span>
            <% {:done, ok, 0} -> %>
              <span class="text-green-600 text-sm">✓ Done — {ok} updated</span>
            <% {:done, ok, err} -> %>
              <span class="text-sm">
                <span class="text-green-600">✓ {ok} ok</span>
                · <span class="text-red-600">{err} failed: {Enum.join(@refresh_errors, ", ")}</span>
              </span>
            <% _ -> %>
          <% end %>
        </div>
      </section>

      <section>
        <h2 class="text-lg font-semibold mb-1">Backfill Live Game State Turns</h2>
        <p class="text-sm text-gray-500 mb-4">
          One-time migration: copies all records from <code>turn_history</code>
          into <code>live_game_state_turns</code>
          for every game. Only run once —
          from then on the new poller keeps the table in sync automatically.
        </p>
        <div class="flex items-center gap-4">
          <button
            phx-click="backfill_all_turns"
            disabled={@backfill_status == :running}
            class="bg-amber-600 text-white px-4 py-2 rounded hover:bg-amber-700 text-sm disabled:opacity-50"
          >
            {if @backfill_status == :running, do: "Running…", else: "Backfill All Games"}
          </button>
          <%= case @backfill_status do %>
            <% :running -> %>
              <span class="text-sm text-gray-500">Working…</span>
            <% {:done, count} -> %>
              <span class="text-green-600 text-sm">✓ {count} rows inserted</span>
            <% _ -> %>
          <% end %>
        </div>
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
                    <a href={"/admin/games/#{game.game_id}"} class="text-blue-600 hover:underline">
                      {game.game_id}
                    </a>
                  </td>
                  <td class="py-2 pr-4">{game.game_name || "—"}</td>
                  <td class="py-2 pr-4">{if turn, do: turn.player.name, else: "—"}</td>
                  <td class="py-2 pr-4">
                    <span class={if alive, do: "text-green-600", else: "text-gray-400"}>
                      {if alive, do: "running", else: "stopped"}
                    </span>
                  </td>
                  <td class="py-2 flex gap-3">
                    <%= if alive do %>
                      <button
                        phx-click="stop_poller"
                        phx-value-game_id={game.game_id}
                        class="text-red-600 hover:underline"
                      >
                        Stop
                      </button>
                    <% else %>
                      <button
                        phx-click="start_poller"
                        phx-value-game_id={game.game_id}
                        class="text-blue-600 hover:underline"
                      >
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

      <section>
        <h2 class="text-lg font-semibold mb-4">Finished Games</h2>
        <%= if Enum.empty?(@finished_games) do %>
          <p class="text-gray-500 text-sm">No finished games on record.</p>
        <% else %>
          <table class="w-full text-sm border-collapse">
            <thead>
              <tr class="text-left border-b border-gray-200">
                <th class="pb-2 pr-4">Game ID</th>
                <th class="pb-2 pr-4">Name</th>
                <th class="pb-2 pr-4">Map</th>
                <th class="pb-2 pr-4">Winners</th>
                <th class="pb-2 pr-4">Finished</th>
                <th class="pb-2">Log</th>
              </tr>
            </thead>
            <tbody>
              <%= for game <- @finished_games do %>
                <tr class="border-b border-gray-100 align-middle">
                  <td class="py-2 pr-4 font-mono">
                    <a href={"/admin/games/#{game.game_id}"} class="text-blue-600 hover:underline">
                      {game.game_id}
                    </a>
                  </td>
                  <td class="py-2 pr-4">{game.game_name || "—"}</td>
                  <td class="py-2 pr-4 text-gray-500">{game.board_name || "—"}</td>
                  <td class="py-2 pr-4 text-gray-600">
                    {if Enum.any?(game.winners),
                      do: Enum.join(game.winners, ", "),
                      else: "—"}
                  </td>
                  <td class="py-2 pr-4 text-gray-500">{game.finished || "—"}</td>
                  <td class="py-2">
                    <%= if MapSet.member?(@snapshot_ids, game.game_id) do %>
                      <span class="text-green-600">✓</span>
                    <% else %>
                      <button
                        phx-click="fetch_historical"
                        phx-value-game_id={game.game_id}
                        disabled={@hist_status == :fetching}
                        class="text-indigo-600 hover:underline disabled:opacity-40 text-xs"
                      >
                        Fetch
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
