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
       refetch_status: nil
     )}
  end

  def handle_event("refetch_and_process", _params, socket) do
    game_id = socket.assigns.game_id
    lv = self()

    Task.start(fn ->
      result = Processor.refetch_and_process(game_id)
      send(lv, {:refetch_result, result})
    end)

    {:noreply, assign(socket, refetch_status: :running)}
  end

  def handle_info({:refetch_result, {:ok, counts}}, socket) do
    {:noreply,
     assign(socket,
       refetch_status: {:ok, counts},
       events: Processor.list_events(socket.assigns.game_id)
     )}
  end

  def handle_info({:refetch_result, {:error, reason}}, socket) do
    {:noreply, assign(socket, refetch_status: {:error, inspect(reason)})}
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-full mx-auto mt-10 px-6 flex flex-col gap-6">
      <div class="flex items-center justify-between">
        <div>
          <a href={"/admin/games/#{@game_id}"} class="text-sm text-blue-600 hover:underline">
            ← {if @game, do: @game.game_name, else: "Game #{@game_id}"}
          </a>
          <h1 class="text-xl font-bold mt-1">Log Events — Game {@game_id}</h1>
          <p class="text-sm text-gray-500">{length(@events)} events</p>
        </div>
        <div class="flex items-center gap-4">
          <button
            phx-click="refetch_and_process"
            disabled={@refetch_status == :running}
            class="bg-blue-600 text-white px-4 py-2 rounded text-sm hover:bg-blue-700 disabled:opacity-50"
          >
            {if @refetch_status == :running, do: "Fetching…", else: "Refetch & Process"}
          </button>
          <%= case @refetch_status do %>
            <% {:ok, counts} -> %>
              <span class="text-sm text-green-600">
                ✓ {counts.new_events} new, {counts.skipped} skipped
              </span>
            <% {:error, reason} -> %>
              <span class="text-sm text-red-600">Error: {reason}</span>
            <% _ -> %>
          <% end %>
        </div>
      </div>

      <%= if Enum.empty?(@events) do %>
        <p class="text-gray-500 text-sm">
          No events processed yet. Click "Refetch & Process" or go to
          <a href="/admin/logs" class="text-blue-600 hover:underline">Admin → Logs</a>
          and run "Process All Snapshots".
        </p>
      <% else %>
        <div class="overflow-x-auto">
          <table class="w-full text-xs border-collapse font-mono whitespace-nowrap">
            <thead class="sticky top-0 bg-white z-10">
              <tr class="text-left border-b-2 border-gray-300 font-sans text-xs font-semibold text-gray-500 uppercase tracking-wide">
                <th class="pb-2 pr-4 sticky left-0 bg-white">Seq</th>
                <th class="pb-2 pr-4">At</th>
                <th class="pb-2 pr-4">Seat</th>
                <th class="pb-2 pr-4">Turn</th>
                <th class="pb-2 pr-4">Type</th>
                <th class="pb-2 pr-4">Player</th>
                <th class="pb-2 pr-4">Defender</th>
                <th class="pb-2 pr-4">From</th>
                <th class="pb-2 pr-4">To</th>
                <th class="pb-2 pr-4">Units</th>
                <th class="pb-2 pr-4">AD</th>
                <th class="pb-2 pr-4">DD</th>
                <th class="pb-2 pr-4">BMod</th>
                <th class="pb-2 pr-4">AL</th>
                <th class="pb-2 pr-4">DL</th>
                <th class="pb-2">Raw Action</th>
              </tr>
            </thead>
            <tbody>
              <%= for e <- @events do %>
                <tr class={[
                  "border-b border-gray-100 align-top hover:bg-gray-50",
                  if(e.event_type == "unrecognized", do: "bg-amber-50 hover:bg-amber-100", else: "")
                ]}>
                  <td class="py-1 pr-4 text-gray-400 sticky left-0 bg-inherit">{e.log_seq}</td>
                  <td class="py-1 pr-4 text-gray-400">{e.occurred_at}</td>
                  <td class="py-1 pr-4 text-gray-400">{e.seat}</td>
                  <td class="py-1 pr-4 text-gray-400">{e.turn_id}</td>
                  <td class={[
                    "py-1 pr-4 font-semibold",
                    if(e.event_type == "unrecognized", do: "text-amber-600", else: "text-blue-700")
                  ]}>
                    {e.event_type}
                  </td>
                  <td class="py-1 pr-4">{e.player}</td>
                  <td class="py-1 pr-4">{e.defender}</td>
                  <td class="py-1 pr-4 text-gray-500">{e.territory_from}</td>
                  <td class="py-1 pr-4">{e.territory_to}</td>
                  <td class="py-1 pr-4">{e.units}</td>
                  <td class="py-1 pr-4 text-gray-500">{e.attacker_dice}</td>
                  <td class="py-1 pr-4 text-gray-500">{e.defender_dice}</td>
                  <td class="py-1 pr-4 text-gray-500">{e.battle_mod}</td>
                  <td class="py-1 pr-4">{e.attacker_losses}</td>
                  <td class="py-1 pr-4">{e.defender_losses}</td>
                  <td class="py-1 text-gray-600 font-sans whitespace-normal max-w-sm">
                    {e.raw_action}
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% end %>
    </div>
    """
  end
end
