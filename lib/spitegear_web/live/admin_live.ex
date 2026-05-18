defmodule SpitegearWeb.AdminLive do
  use SpitegearWeb, :live_view
  alias Spitegear.MessageTemplates
  alias Spitegear.Settings

  @cookie_key "wargear_cookie"
  @api_key_key "wargear_api_key"

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       cookie: Settings.get(@cookie_key) || "",
       api_key: Settings.get(@api_key_key) || "",
       saved: nil,
       revealed: MapSet.new(),
       global_templates: MessageTemplates.list_global(),
       saved_template: nil
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

  def handle_event("save_template", %{"key" => key, "template" => template}, socket) do
    MessageTemplates.put(key, template)
    {:noreply, assign(socket, global_templates: MessageTemplates.list_global(), saved_template: key)}
  end

  def handle_event("reset_template", %{"key" => key}, socket) do
    MessageTemplates.delete(key)
    {:noreply, assign(socket, global_templates: MessageTemplates.list_global(), saved_template: nil)}
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
        <a href="/admin/games" class="text-sm text-blue-600 hover:underline">Games →</a>
      </div>

      <section>
        <h2 class="text-lg font-semibold mb-3">Wargear API Key</h2>
        <.secret_row key="wargear_api_key" value={@api_key} revealed={revealed?(@revealed, "wargear_api_key")} />
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
        <.secret_row key="wargear_cookie" value={@cookie} revealed={revealed?(@revealed, "wargear_cookie")} />
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
      <section>
        <h2 class="text-lg font-semibold mb-3">Message Templates</h2>
        <p class="text-sm text-gray-500 mb-4">
          Global defaults for all games. Use <code class="bg-gray-100 px-1 rounded">%{"{var}"}</code> for variables.
        </p>
        <div class="flex flex-col gap-6">
          <%= for key <- MessageTemplates.all_keys() do %>
            <% key_str = to_string(key) %>
            <% custom = Map.get(@global_templates, key_str) %>
            <div class="border border-gray-200 rounded p-4">
              <div class="flex items-center justify-between mb-1">
                <span class="text-sm font-medium font-mono"><%= key_str %></span>
                <div class="flex items-center gap-3">
                  <%= if custom do %>
                    <span class="text-xs text-blue-600 font-medium">custom</span>
                    <button
                      phx-click="reset_template"
                      phx-value-key={key_str}
                      class="text-xs text-red-500 hover:underline"
                    >
                      Reset to default
                    </button>
                  <% else %>
                    <span class="text-xs text-gray-400">default</span>
                  <% end %>
                </div>
              </div>
              <p class="text-xs text-gray-400 mb-2">
                vars: <%= Enum.join(MessageTemplates.available_vars(key), ", ") %>
              </p>
              <form phx-submit="save_template" class="flex flex-col gap-2">
                <input type="hidden" name="key" value={key_str} />
                <textarea
                  name="template"
                  rows="2"
                  class="w-full font-mono text-sm border border-gray-300 rounded p-2"
                ><%= custom || MessageTemplates.default_template(key) %></textarea>
                <div class="flex items-center gap-3">
                  <button type="submit" class="text-sm text-blue-600 hover:underline">Save</button>
                  <%= if @saved_template == key_str do %>
                    <span class="text-green-600 text-xs">Saved</span>
                  <% end %>
                </div>
              </form>
            </div>
          <% end %>
        </div>
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
