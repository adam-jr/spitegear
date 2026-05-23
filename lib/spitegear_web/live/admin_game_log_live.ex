defmodule SpitegearWeb.AdminGameLogLive do
  use SpitegearWeb, :live_view
  alias Spitegear.GameLog.Processor
  alias Spitegear.Games

  def mount(%{"game_id" => game_id}, _session, socket) do
    {:ok,
     assign(socket,
       game_id: game_id,
       game: Games.get_game(game_id),
       events: Processor.list_events(game_id),
       expanded: MapSet.new()
     )}
  end

  def handle_event("toggle_row", %{"seq" => seq_str}, socket) do
    seq = String.to_integer(seq_str)

    expanded =
      if MapSet.member?(socket.assigns.expanded, seq) do
        MapSet.delete(socket.assigns.expanded, seq)
      else
        MapSet.put(socket.assigns.expanded, seq)
      end

    {:noreply, assign(socket, expanded: expanded)}
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-full mx-auto mt-10 px-6 flex flex-col gap-6">
      <div class="flex items-center justify-between">
        <div>
          <a href={"/admin/games/#{@game_id}"} class="text-sm text-blue-600 hover:underline">
            ← <%= if @game, do: @game.game_name, else: "Game #{@game_id}" %>
          </a>
          <h1 class="text-xl font-bold mt-1">Log Events — Game <%= @game_id %></h1>
          <p class="text-sm text-gray-500"><%= length(@events) %> events</p>
        </div>
      </div>

      <%= if Enum.empty?(@events) do %>
        <p class="text-gray-500 text-sm">
          No events processed yet. Go to
          <a href="/admin/logs" class="text-blue-600 hover:underline">Admin → Logs</a>
          and run "Process All Snapshots".
        </p>
      <% else %>
        <div class="overflow-x-auto">
          <table class="text-xs border-collapse font-mono whitespace-nowrap w-full">
            <thead>
              <tr class="text-left border-b border-gray-300 font-sans text-xs font-semibold text-gray-500 uppercase tracking-wide">
                <th class="pb-2 pr-1 w-4"></th>
                <th class="pb-2 pr-3">Seq</th>
                <th class="pb-2 pr-3">At</th>
                <th class="pb-2 pr-3">Seat</th>
                <th class="pb-2 pr-3">Turn</th>
                <th class="pb-2 pr-3">Type</th>
                <th class="pb-2 pr-3">Attacker</th>
                <th class="pb-2 pr-3">Defender</th>
                <th class="pb-2 pr-3">From</th>
                <th class="pb-2 pr-3">To</th>
                <th class="pb-2 pr-3">Units</th>
                <th class="pb-2 pr-3">AD</th>
                <th class="pb-2 pr-3">DD</th>
                <th class="pb-2 pr-3">BMod</th>
                <th class="pb-2 pr-3">AL</th>
                <th class="pb-2">DL</th>
              </tr>
            </thead>
            <tbody>
              <%= for e <- @events do %>
                <tr class={[
                  "border-b border-gray-100 align-top cursor-pointer hover:bg-gray-50",
                  if(e.event_type == "unrecognized", do: "bg-amber-50 hover:bg-amber-100", else: "")
                ]}>
                  <td class="py-1 pr-1">
                    <button
                      phx-click="toggle_row"
                      phx-value-seq={e.log_seq}
                      class="text-gray-400 hover:text-gray-700 leading-none"
                      title="Show raw action"
                    >
                      <%= if MapSet.member?(@expanded, e.log_seq), do: "▼", else: "▶" %>
                    </button>
                  </td>
                  <td class="py-1 pr-3 text-gray-400"><%= e.log_seq %></td>
                  <td class="py-1 pr-3 text-gray-400"><%= e.occurred_at %></td>
                  <td class="py-1 pr-3 text-gray-400"><%= e.seat %></td>
                  <td class="py-1 pr-3 text-gray-400"><%= e.turn_id %></td>
                  <td class={[
                    "py-1 pr-3 font-semibold",
                    if(e.event_type == "unrecognized", do: "text-amber-600", else: "text-blue-700")
                  ]}>
                    <%= e.event_type %>
                  </td>
                  <td class="py-1 pr-3"><%= e.attacker %></td>
                  <td class="py-1 pr-3 text-gray-500"><%= e.defender %></td>
                  <td class="py-1 pr-3 text-gray-500"><%= e.territory_from %></td>
                  <td class="py-1 pr-3"><%= e.territory_to %></td>
                  <td class="py-1 pr-3"><%= e.units %></td>
                  <td class="py-1 pr-3 text-gray-500"><%= e.attacker_dice %></td>
                  <td class="py-1 pr-3 text-gray-500"><%= e.defender_dice %></td>
                  <td class="py-1 pr-3 text-gray-500"><%= e.battle_mod %></td>
                  <td class="py-1 pr-3"><%= e.attacker_losses %></td>
                  <td class="py-1"><%= e.defender_losses %></td>
                </tr>
                <%= if MapSet.member?(@expanded, e.log_seq) do %>
                  <tr class={if(e.event_type == "unrecognized", do: "bg-amber-50", else: "bg-gray-50")}>
                    <td></td>
                    <td colspan="15" class="py-2 pr-4 pb-3">
                      <span class="font-sans text-gray-400 text-xs uppercase tracking-wide mr-2">raw</span>
                      <span class="font-mono text-gray-800 text-xs break-all whitespace-normal"><%= e.raw_action %></span>
                    </td>
                  </tr>
                <% end %>
              <% end %>
            </tbody>
          </table>
        </div>
      <% end %>
    </div>
    """
  end
end
