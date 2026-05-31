defmodule SpitegearWeb.AdminLogsLive do
  use SpitegearWeb, :live_view
  alias Spitegear.GameLog.Processor

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       summary: Processor.summary(),
       event_counts: Processor.event_type_counts(),
       unrecognized: Processor.list_unrecognized(),
       process_status: nil,
       reprocess_status: nil,
       fill_defenders_status: nil,
       refetch_all_status: nil
     )}
  end

  def handle_event("process_all", _params, socket) do
    start_task(:process_all, self())
    {:noreply, assign(socket, process_status: :running)}
  end

  def handle_event("reprocess_unrecognized", _params, socket) do
    start_task(:reprocess_unrecognized, self())
    {:noreply, assign(socket, reprocess_status: :running)}
  end

  def handle_event("fill_defenders", _params, socket) do
    start_task(:fill_defenders, self())
    {:noreply, assign(socket, fill_defenders_status: :running)}
  end

  def handle_event("refetch_all", _params, socket) do
    start_task(:refetch_all, self())
    {:noreply, assign(socket, refetch_all_status: :running)}
  end

  def handle_info({:task_result, :process_all, {:ok, counts}}, socket) do
    {:noreply,
     assign(socket,
       process_status: {:ok, counts},
       summary: Processor.summary(),
       event_counts: Processor.event_type_counts(),
       unrecognized: Processor.list_unrecognized()
     )}
  end

  def handle_info({:task_result, :process_all, {:error, reason}}, socket) do
    {:noreply, assign(socket, process_status: {:error, inspect(reason)})}
  end

  def handle_info({:task_result, :reprocess_unrecognized, {:ok, counts}}, socket) do
    {:noreply,
     assign(socket,
       reprocess_status: {:ok, counts},
       summary: Processor.summary(),
       event_counts: Processor.event_type_counts(),
       unrecognized: Processor.list_unrecognized()
     )}
  end

  def handle_info({:task_result, :reprocess_unrecognized, {:error, reason}}, socket) do
    {:noreply, assign(socket, reprocess_status: {:error, inspect(reason)})}
  end

  def handle_info({:task_result, :fill_defenders, {:ok, counts}}, socket) do
    {:noreply,
     assign(socket,
       fill_defenders_status: {:ok, counts},
       summary: Processor.summary()
     )}
  end

  def handle_info({:task_result, :fill_defenders, {:error, reason}}, socket) do
    {:noreply, assign(socket, fill_defenders_status: {:error, inspect(reason)})}
  end

  def handle_info({:task_result, :refetch_all, {:ok, counts}}, socket) do
    {:noreply,
     assign(socket,
       refetch_all_status: {:ok, counts},
       summary: Processor.summary(),
       event_counts: Processor.event_type_counts(),
       unrecognized: Processor.list_unrecognized()
     )}
  end

  def handle_info({:task_result, :refetch_all, {:error, reason}}, socket) do
    {:noreply, assign(socket, refetch_all_status: {:error, inspect(reason)})}
  end

  defp start_task(action, lv) do
    Task.start(fn ->
      result =
        case action do
          :process_all -> Processor.process_all()
          :reprocess_unrecognized -> Processor.reprocess_unrecognized()
          :fill_defenders -> Processor.fill_defenders()
          :refetch_all -> Processor.refetch_all()
        end

      send(lv, {:task_result, action, result})
    end)
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto mt-16 p-6 flex flex-col gap-10">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">Game Log Processing</h1>
        <a href="/admin" class="text-sm text-blue-600 hover:underline">← Settings</a>
      </div>

      <%!-- Summary stats --%>
      <section class="grid grid-cols-3 gap-4">
        <div class="border rounded p-4 text-center">
          <div class="text-3xl font-bold">{@summary.total}</div>
          <div class="text-sm text-gray-500 mt-1">Total Events</div>
        </div>
        <div class="border rounded p-4 text-center">
          <div class="text-3xl font-bold">{@summary.games_processed}</div>
          <div class="text-sm text-gray-500 mt-1">Games Processed</div>
        </div>
        <div class={[
          "border rounded p-4 text-center",
          if(@summary.unrecognized > 0, do: "border-amber-400 bg-amber-50", else: "")
        ]}>
          <div class={[
            "text-3xl font-bold",
            if(@summary.unrecognized > 0, do: "text-amber-600", else: "")
          ]}>
            {@summary.unrecognized}
          </div>
          <div class="text-sm text-gray-500 mt-1">Unrecognized</div>
        </div>
      </section>

      <%!-- Actions --%>
      <section class="flex gap-6 items-start">
        <div class="flex flex-col gap-2">
          <button
            phx-click="process_all"
            disabled={@process_status == :running}
            class="bg-blue-600 text-white px-5 py-2 rounded hover:bg-blue-700 disabled:opacity-50 text-sm"
          >
            {if @process_status == :running, do: "Processing…", else: "Process All Snapshots"}
          </button>
          <%= case @process_status do %>
            <% {:ok, counts} -> %>
              <span class="text-green-600 text-sm">
                ✓ Done — {counts.upserted} upserted, {counts.unrecognized} unrecognized
              </span>
            <% {:error, reason} -> %>
              <span class="text-red-600 text-sm">Error: {reason}</span>
            <% _ -> %>
          <% end %>
        </div>

        <div class="flex flex-col gap-2">
          <button
            phx-click="reprocess_unrecognized"
            disabled={@reprocess_status == :running or @summary.unrecognized == 0}
            class="bg-amber-600 text-white px-5 py-2 rounded hover:bg-amber-700 disabled:opacity-50 text-sm"
          >
            {if @reprocess_status == :running, do: "Reprocessing…", else: "Reprocess Unrecognized"}
          </button>
          <%= case @reprocess_status do %>
            <% {:ok, counts} -> %>
              <span class="text-green-600 text-sm">
                ✓ {counts.resolved} resolved, {counts.still_unrecognized} remain
              </span>
            <% {:error, reason} -> %>
              <span class="text-red-600 text-sm">Error: {reason}</span>
            <% _ -> %>
          <% end %>
        </div>

        <div class="flex flex-col gap-2">
          <button
            phx-click="refetch_all"
            disabled={@refetch_all_status == :running}
            class="bg-indigo-600 text-white px-5 py-2 rounded hover:bg-indigo-700 disabled:opacity-50 text-sm"
          >
            {if @refetch_all_status == :running, do: "Refetching…", else: "Refetch All Logs"}
          </button>
          <p class="text-xs text-gray-400 max-w-xs">
            Re-downloads each game log with setup events (?showsetup=1) and inserts new seqs only.
          </p>
          <%= case @refetch_all_status do %>
            <% {:ok, counts} -> %>
              <span class="text-green-600 text-sm">
                ✓ {counts.new_events} new, {counts.skipped} skipped
              </span>
            <% {:error, reason} -> %>
              <span class="text-red-600 text-sm">Error: {reason}</span>
            <% _ -> %>
          <% end %>
        </div>

        <div class="flex flex-col gap-2">
          <button
            phx-click="fill_defenders"
            disabled={@fill_defenders_status == :running or @summary.pending_defenders == 0}
            class="bg-emerald-600 text-white px-5 py-2 rounded hover:bg-emerald-700 disabled:opacity-50 text-sm"
          >
            <%= if @fill_defenders_status == :running do %>
              Filling…
            <% else %>
              Fill Defenders
              <%= if @summary.pending_defenders > 0 do %>
                <span class="ml-1.5 bg-white/20 rounded px-1.5 py-0.5 text-xs tabular-nums">
                  {@summary.pending_defenders} pending
                </span>
              <% end %>
            <% end %>
          </button>
          <p class="text-xs text-gray-400 max-w-xs">
            Backfills defender + territory_from on attacked/occupied events using per-game player names.
          </p>
          <%= case @fill_defenders_status do %>
            <% {:ok, counts} -> %>
              <p class="text-sm text-green-700 font-medium">✓ Done</p>
              <table class="text-xs text-gray-700 mt-0.5 tabular-nums">
                <tr>
                  <td class="pr-3 text-gray-400">Attempted</td>
                  <td>{counts.attempted}</td>
                </tr>
                <tr>
                  <td class="pr-3 text-gray-400">Filled</td>
                  <td class="text-green-700 font-semibold">{counts.filled}</td>
                </tr>
                <tr>
                  <td class="pr-3 text-gray-400">Still unfilled</td>
                  <td class={if(counts.unfilled > 0, do: "text-amber-600 font-semibold", else: "")}>
                    {counts.unfilled}
                  </td>
                </tr>
              </table>
            <% {:error, reason} -> %>
              <span class="text-red-600 text-sm">Error: {reason}</span>
            <% _ -> %>
              <%= if @summary.pending_defenders == 0 do %>
                <span class="text-xs text-gray-400">No events pending — all defenders filled.</span>
              <% end %>
          <% end %>
        </div>
      </section>

      <%!-- Event type breakdown --%>
      <section>
        <h2 class="text-lg font-semibold mb-3">Event Types</h2>
        <%= if Enum.empty?(@event_counts) do %>
          <p class="text-gray-500 text-sm">No events processed yet.</p>
        <% else %>
          <table class="w-full text-sm border-collapse">
            <thead>
              <tr class="text-left border-b border-gray-200">
                <th class="pb-2 pr-6">Event Type</th>
                <th class="pb-2 text-right">Count</th>
              </tr>
            </thead>
            <tbody>
              <%= for row <- @event_counts do %>
                <tr class={[
                  "border-b border-gray-100",
                  if(row.event_type == "unrecognized", do: "bg-amber-50", else: "")
                ]}>
                  <td class={[
                    "py-1.5 pr-6 font-mono text-xs",
                    if(row.event_type == "unrecognized", do: "text-amber-700 font-semibold", else: "")
                  ]}>
                    {row.event_type}
                  </td>
                  <td class="py-1.5 text-right tabular-nums">{row.count}</td>
                </tr>
              <% end %>
            </tbody>
          </table>
        <% end %>
      </section>

      <%!-- Unrecognized event groomer --%>
      <%= if Enum.any?(@unrecognized) do %>
        <section>
          <h2 class="text-lg font-semibold mb-1">Unrecognized Events</h2>
          <p class="text-sm text-gray-500 mb-3">
            These action strings didn't match any known pattern. Add patterns to the parser, then hit Reprocess Unrecognized.
          </p>
          <div class="overflow-x-auto">
            <table class="w-full text-xs border-collapse font-mono">
              <thead>
                <tr class="text-left border-b border-gray-200 font-sans text-sm font-medium">
                  <th class="pb-2 pr-4">Game</th>
                  <th class="pb-2 pr-4">Seq</th>
                  <th class="pb-2 pr-4">Seat</th>
                  <th class="pb-2 pr-4">At</th>
                  <th class="pb-2">Raw Action</th>
                </tr>
              </thead>
              <tbody>
                <%= for event <- @unrecognized do %>
                  <tr class="border-b border-gray-100 align-top">
                    <td class="py-1.5 pr-4 text-blue-600">
                      <a href={"/admin/games/#{event.game_id}"} class="hover:underline">
                        {event.game_id}
                      </a>
                    </td>
                    <td class="py-1.5 pr-4 text-gray-500">{event.log_seq}</td>
                    <td class="py-1.5 pr-4 text-gray-500">{event.seat}</td>
                    <td class="py-1.5 pr-4 text-gray-400 whitespace-nowrap">
                      {event.occurred_at}
                    </td>
                    <td class="py-1.5 text-gray-800 break-all">{event.raw_action}</td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </section>
      <% end %>
    </div>
    """
  end
end
