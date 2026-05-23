defmodule SpitegearWeb.AdminLive do
  use SpitegearWeb, :live_view
  alias Spitegear.Settings

  @cookie_key "wargear_cookie"
  @api_key_key "wargear_api_key"
  @slack_name_key "admin_slack_name"

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       cookie: Settings.get(@cookie_key) || "",
       api_key: Settings.get(@api_key_key) || "",
       slack_name: Settings.get(@slack_name_key) || "",
       saved: nil,
       revealed: MapSet.new()
     )}
  end

  def handle_event("save_cookie", %{"cookie" => value}, socket) do
    {:ok, _} = Settings.put(@cookie_key, value)
    {:noreply, assign(socket, cookie: value, saved: :cookie)}
  end

  def handle_event("save_api_key", %{"api_key" => value}, socket) do
    {:ok, _} = Settings.put(@api_key_key, value)
    {:noreply, assign(socket, api_key: value, saved: :api_key)}
  end

  def handle_event("save_slack_name", %{"slack_name" => value}, socket) do
    {:ok, _} = Settings.put(@slack_name_key, value)
    {:noreply, assign(socket, slack_name: value, saved: :slack_name)}
  end

  def handle_event("toggle_reveal", %{"key" => key}, socket) do
    revealed =
      if MapSet.member?(socket.assigns.revealed, key) do
        MapSet.delete(socket.assigns.revealed, key)
      else
        MapSet.put(socket.assigns.revealed, key)
      end

    {:noreply, assign(socket, revealed: revealed)}
  end

  defp revealed?(revealed, key), do: MapSet.member?(revealed, key)

  def render(assigns) do
    ~H"""
    <div class="max-w-xl mx-auto mt-16 p-6 flex flex-col gap-10">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">Admin</h1>
        <div class="flex items-center gap-4">
          <a href="/admin/templates" class="text-sm text-blue-600 hover:underline">Templates →</a>
          <a href="/admin/logs" class="text-sm text-blue-600 hover:underline">Logs →</a>
          <a href="/admin/games" class="text-sm text-blue-600 hover:underline">Games →</a>
        </div>
      </div>

      <section>
        <h2 class="text-lg font-semibold mb-3">Your Slack Name</h2>
        <p class="text-sm text-gray-500 mb-3">Used as the player in template test messages.</p>
        <form phx-submit="save_slack_name" class="flex flex-col gap-4">
          <input
            type="text"
            name="slack_name"
            value={@slack_name}
            class="w-full font-mono text-sm border border-gray-300 rounded p-2"
            placeholder="e.g. @yourname"
          />
          <div class="flex items-center gap-4">
            <button type="submit" class="bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700">
              Save
            </button>
            <%= if @saved == :slack_name do %>
              <span class="text-green-600 text-sm">Saved</span>
            <% end %>
          </div>
        </form>
      </section>

      <section>
        <h2 class="text-lg font-semibold mb-3">Wargear API Key</h2>
        <.secret_row
          key="wargear_api_key"
          value={@api_key}
          revealed={revealed?(@revealed, "wargear_api_key")}
        />
        <form phx-submit="save_api_key" class="flex flex-col gap-4 mt-4">
          <input
            type="text"
            name="api_key"
            value={@api_key}
            class="w-full font-mono text-sm border border-gray-300 rounded p-2"
            placeholder="Your wargear.net API key"
          />
          <div class="flex items-center gap-4">
            <button type="submit" class="bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700">
              Save
            </button>
            <%= if @saved == :api_key do %>
              <span class="text-green-600 text-sm">Saved</span>
            <% end %>
          </div>
        </form>
      </section>

      <section>
        <h2 class="text-lg font-semibold mb-3">Wargear Session Cookie</h2>
        <.secret_row
          key="wargear_cookie"
          value={@cookie}
          revealed={revealed?(@revealed, "wargear_cookie")}
        />
        <form phx-submit="save_cookie" class="flex flex-col gap-4 mt-4">
          <textarea
            name="cookie"
            rows="4"
            class="w-full font-mono text-sm border border-gray-300 rounded p-2"
            placeholder="Paste cookie string here"
          ><%= @cookie %></textarea>
          <div class="flex items-center gap-4">
            <button type="submit" class="bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700">
              Save
            </button>
            <%= if @saved == :cookie do %>
              <span class="text-green-600 text-sm">Saved</span>
            <% end %>
          </div>
        </form>
      </section>
    </div>
    """
  end

  defp secret_row(assigns) do
    ~H"""
    <div class="flex items-center gap-3 font-mono text-sm bg-gray-50 border border-gray-200 rounded p-2">
      <span class="flex-1 truncate text-gray-700">
        <%= if @revealed, do: @value, else: mask(@value) %>
      </span>
      <button
        type="button"
        phx-click="toggle_reveal"
        phx-value-key={@key}
        class="text-xs text-blue-600 hover:underline shrink-0"
      >
        <%= if @revealed, do: "Hide", else: "Reveal" %>
      </button>
      <%= if @revealed and @value != "" do %>
        <button
          type="button"
          data-value={@value}
          onclick="navigator.clipboard.writeText(this.dataset.value).then(() => { this.textContent = 'Copied!'; setTimeout(() => this.textContent = 'Copy', 1500) })"
          class="text-xs text-gray-500 hover:underline shrink-0"
        >
          Copy
        </button>
      <% end %>
    </div>
    """
  end

  defp mask(""), do: "—"
  defp mask(value), do: String.slice(value, 0, 6) <> String.duplicate("•", 20)
end
