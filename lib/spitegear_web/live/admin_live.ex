defmodule SpitegearWeb.AdminLive do
  use SpitegearWeb, :live_view
  alias Spitegear.Settings

  @cookie_key "wargear_cookie"
  @api_key_key "wargear_api_key"

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       cookie: Settings.get(@cookie_key) || "",
       api_key: Settings.get(@api_key_key) || "",
       saved: nil
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

  def render(assigns) do
    ~H"""
    <div class="max-w-xl mx-auto mt-16 p-6 flex flex-col gap-10">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">Admin</h1>
        <a href="/admin/games" class="text-sm text-blue-600 hover:underline">Games →</a>
      </div>

      <section>
        <h2 class="text-lg font-semibold mb-4">Wargear API Key</h2>
        <form phx-submit="save_api_key" class="flex flex-col gap-4">
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
        <h2 class="text-lg font-semibold mb-4">Wargear Session Cookie</h2>
        <form phx-submit="save_cookie" class="flex flex-col gap-4">
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
end
