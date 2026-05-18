defmodule SpitegearWeb.AdminTemplatesLive do
  use SpitegearWeb, :live_view
  alias Spitegear.MessageTemplates
  alias Spitegear.PubSub

  def mount(params, _session, socket) do
    game_id = Map.get(params, "game_id")
    {game_templates, global_templates} = load_templates(game_id)

    gif_preview_url = current_gif_url(game_id, game_templates, global_templates)

    {:ok,
     assign(socket,
       game_id: game_id,
       game_templates: game_templates,
       global_templates: global_templates,
       saved_template: nil,
       gif_preview_url: gif_preview_url
     )}
  end

  def handle_event("save_template", %{"key" => key, "template" => template}, socket) do
    MessageTemplates.put(key, template, socket.assigns.game_id)
    {game_templates, global_templates} = load_templates(socket.assigns.game_id)

    gif_preview_url =
      if key == "game_winners_gif",
        do: template,
        else: socket.assigns.gif_preview_url

    {:noreply,
     assign(socket,
       game_templates: game_templates,
       global_templates: global_templates,
       saved_template: key,
       gif_preview_url: gif_preview_url
     )}
  end

  def handle_event("reset_template", %{"key" => key}, socket) do
    MessageTemplates.delete(key, socket.assigns.game_id)
    {game_templates, global_templates} = load_templates(socket.assigns.game_id)

    gif_preview_url =
      if key == "game_winners_gif",
        do: current_gif_url(socket.assigns.game_id, game_templates, global_templates),
        else: socket.assigns.gif_preview_url

    {:noreply,
     assign(socket,
       game_templates: game_templates,
       global_templates: global_templates,
       saved_template: nil,
       gif_preview_url: gif_preview_url
     )}
  end

  def handle_event("update_gif_preview", %{"template" => url}, socket) do
    {:noreply, assign(socket, gif_preview_url: url)}
  end

  def handle_event("test_template", %{"key" => "game_winners"}, socket) do
    game_id = socket.assigns.game_id
    slack_name = Spitegear.Settings.get("admin_slack_name") || "@testplayer"
    player = %{slack_name: slack_name}

    {blocks, fallback} =
      MessageTemplates.game_winners_blocks([player], game_id || "00000000", "Test Game")

    PubSub.msg(:spitegear_test, type: :game_winners, payload: {blocks, fallback})
    {:noreply, socket}
  end

  def handle_event("test_template", %{"key" => key}, socket) do
    text = MessageTemplates.render_sample(key, socket.assigns.game_id)
    PubSub.msg(:spitegear_test, text)
    {:noreply, socket}
  end

  defp load_templates(nil), do: {%{}, MessageTemplates.list_global()}

  defp load_templates(game_id),
    do: {MessageTemplates.list_for_game(game_id), MessageTemplates.list_global()}

  defp current_gif_url(game_id, game_templates, global_templates) do
    if(game_id, do: Map.get(game_templates, "game_winners_gif")) ||
      Map.get(global_templates, "game_winners_gif") ||
      MessageTemplates.default_template(:game_winners_gif)
  end

  defp back_path(nil), do: "/admin"
  defp back_path(game_id), do: "/admin/games/#{game_id}"

  def render(assigns) do
    ~H"""
    <div class="max-w-xl mx-auto mt-16 p-6 flex flex-col gap-10">
      <div>
        <a href={back_path(@game_id)} class="text-sm text-blue-600 hover:underline">
          <%= if @game_id, do: "← Game", else: "← Admin" %>
        </a>
        <h1 class="text-2xl font-bold mt-1">Message Templates</h1>
        <p class="text-sm text-gray-500 mt-1">
          <%= if @game_id do %>
            Game-specific overrides — falls back to global if not set.
          <% else %>
            Global defaults for all games.
          <% end %>
          Use <code class="bg-gray-100 px-1 rounded">%{"{var}"}</code>
          for variables.
        </p>
      </div>

      <div class="flex flex-col gap-6">
        <%= for key <- MessageTemplates.all_keys() do %>
          <% key_str = to_string(key) %>
          <% game_custom = if @game_id, do: Map.get(@game_templates, key_str) %>
          <% global_custom = Map.get(@global_templates, key_str) %>
          <% active = game_custom || if(is_nil(@game_id), do: global_custom) %>
          <div class="border border-gray-200 rounded p-4">
            <div class="flex items-center justify-between mb-1">
              <span class="text-sm font-medium font-mono"><%= key_str %></span>
              <div class="flex items-center gap-3">
                <%= cond do %>
                  <% @game_id && game_custom -> %>
                    <span class="text-xs text-blue-600 font-medium">game override</span>
                    <button
                      phx-click="reset_template"
                      phx-value-key={key_str}
                      class="text-xs text-red-500 hover:underline"
                    >
                      Reset to <%= if global_custom, do: "global", else: "default" %>
                    </button>
                  <% @game_id && global_custom -> %>
                    <span class="text-xs text-yellow-600 font-medium">global</span>
                  <% is_nil(@game_id) && global_custom -> %>
                    <span class="text-xs text-blue-600 font-medium">custom</span>
                    <button
                      phx-click="reset_template"
                      phx-value-key={key_str}
                      class="text-xs text-red-500 hover:underline"
                    >
                      Reset to default
                    </button>
                  <% true -> %>
                    <span class="text-xs text-gray-400">default</span>
                <% end %>
              </div>
            </div>
            <%= if MessageTemplates.available_vars(key) != [] do %>
              <p class="text-xs text-gray-400 mb-2">
                vars: <%= Enum.join(MessageTemplates.available_vars(key), ", ") %>
              </p>
            <% end %>
            <form
              phx-submit="save_template"
              phx-change={if key_str == "game_winners_gif", do: "update_gif_preview"}
              class="flex flex-col gap-2"
            >
              <input type="hidden" name="key" value={key_str} />
              <textarea
                name="template"
                rows={if key_str == "game_winners_gif", do: "1", else: "2"}
                class="w-full font-mono text-sm border border-gray-300 rounded p-2"
              ><%= active || MessageTemplates.default_template(key) %></textarea>
              <%= if key_str == "game_winners_gif" do %>
                <img
                  src={@gif_preview_url}
                  alt="GIF preview"
                  class="max-h-28 w-auto self-start rounded mt-1"
                />
              <% end %>
              <div class="flex items-center gap-3">
                <button type="submit" class="text-sm text-blue-600 hover:underline">Save</button>
                <%= if key_str != "game_winners_gif" do %>
                  <button
                    type="button"
                    phx-click="test_template"
                    phx-value-key={key_str}
                    class="text-sm text-gray-500 hover:underline"
                  >
                    Test →#spitegear-test
                  </button>
                <% end %>
                <%= if @saved_template == key_str do %>
                  <span class="text-green-600 text-xs">Saved</span>
                <% end %>
              </div>
            </form>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
