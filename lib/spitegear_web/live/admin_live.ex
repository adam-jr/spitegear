defmodule SpitegearWeb.AdminLive do
  use SpitegearWeb, :live_view
  alias Spitegear.Settings

  @cookie_key "wargear_cookie"

  def mount(_params, _session, socket) do
    cookie = Settings.get(@cookie_key) || ""
    {:ok, assign(socket, cookie: cookie, saved: false)}
  end

  def handle_event("save", %{"cookie" => value}, socket) do
    {:ok, _} = Settings.put(@cookie_key, value)
    {:noreply, assign(socket, cookie: value, saved: true)}
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-xl mx-auto mt-16 p-6">
      <h1 class="text-2xl font-bold mb-8">Admin</h1>

      <section>
        <h2 class="text-lg font-semibold mb-4">Wargear Session Cookie</h2>
        <form phx-submit="save" class="flex flex-col gap-4">
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
            <%= if @saved do %>
              <span class="text-green-600 text-sm">Saved</span>
            <% end %>
          </div>
        </form>
      </section>
    </div>
    """
  end
end
