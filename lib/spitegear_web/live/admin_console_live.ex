defmodule SpitegearWeb.AdminConsoleLive do
  use SpitegearWeb, :live_view

  @preamble """
  alias Spitegear.Repo
  import Ecto.Query
  alias Spitegear.Game
  alias Spitegear.GameDeath
  alias Spitegear.GameDeaths
  alias Spitegear.GameLogEvent
  alias Spitegear.GameLogSnapshot
  alias Spitegear.GameMapImage
  alias Spitegear.GameMaps
  alias Spitegear.Games
  alias Spitegear.LiveGameState
  alias Spitegear.LiveGameState.HistoryResponses
  alias Spitegear.LiveGameState.Turn
  alias Spitegear.LiveGameState.Turns
  alias Spitegear.LiveGameState.ViewScreen
  alias Spitegear.LiveGameState.ViewScreens
  alias Spitegear.LiveGameState.WargearHistoryApiResponseDb
  alias Spitegear.LiveGameState.WargearViewScreenDb
  alias Spitegear.MessageTemplate
  alias Spitegear.MessageTemplates
  alias Spitegear.PubSub
  alias Spitegear.Setting
  alias Spitegear.Settings
  alias Spitegear.TurnHistory
  alias Spitegear.Accounts
  alias Spitegear.Accounts.User
  alias Spitegear.Worker.GameManager
  alias Spitegear.Worker.GamePoller
  alias Spitegear.Worker.SlackMessenger
  alias Spitegear.GameLog.Parser, as: LogParser
  alias Spitegear.GameLog.Processor, as: LogProcessor
  alias Spitegear.Slack.API, as: SlackAPI
  alias Spitegear.Slack.Message, as: SlackMessage
  alias Spitegear.Wargear.HTTP.History, as: WargearHistory
  alias Spitegear.Wargear.HTTP.Login, as: WargearLogin
  alias Spitegear.Wargear.HTTP.LogSnapshot, as: WargearLogSnapshot
  """

  @context [
    {"DB", ["Repo", "import Ecto.Query"]},
    {"Schemas",
     [
       "Game",
       "GameDeath",
       "GameLogEvent",
       "GameLogSnapshot",
       "GameMapImage",
       "MessageTemplate",
       "Setting",
       "TurnHistory",
       "Turn",
       "User"
     ]},
    {"Contexts", ["Games", "GameDeaths", "GameMaps", "MessageTemplates", "Settings", "Accounts"]},
    {"LiveGameState",
     [
       "LiveGameState",
       "Turns",
       "ViewScreen",
       "ViewScreens",
       "HistoryResponses",
       "WargearViewScreenDb",
       "WargearHistoryApiResponseDb"
     ]},
    {"Workers", ["GameManager", "GamePoller", "SlackMessenger"]},
    {"Wargear HTTP", ["WargearHistory", "WargearLogin", "WargearLogSnapshot"]},
    {"Game Log", ["LogParser", "LogProcessor"]},
    {"Slack", ["SlackAPI", "SlackMessage", "PubSub"]}
  ]

  def mount(_params, _session, socket) do
    {:ok, assign(socket, code: "", result: nil, history: [], bindings: [], context: @context)}
  end

  def handle_event("eval", %{"code" => ""}, socket), do: {:noreply, socket}

  def handle_event("eval", %{"code" => code}, socket) do
    {result, new_bindings} = safe_eval(code, socket.assigns.bindings)
    history = [%{code: code, result: result} | socket.assigns.history] |> Enum.take(30)

    {:noreply,
     assign(socket, code: code, result: result, history: history, bindings: new_bindings)}
  end

  def handle_event("clear", _params, socket) do
    {:noreply, assign(socket, history: [], bindings: [], result: nil)}
  end

  defp safe_eval(code, bindings) do
    {value, new_bindings} = Code.eval_string(@preamble <> "\n" <> code, bindings)
    {{:ok, inspect(value, pretty: true, limit: 200, printable_limit: :infinity)}, new_bindings}
  rescue
    e ->
      msg = Exception.format(:error, e, __STACKTRACE__)
      {{:error, msg}, bindings}
  catch
    kind, reason ->
      msg = Exception.format(kind, reason, __STACKTRACE__)
      {{:error, msg}, bindings}
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto mt-8 p-6 flex flex-col gap-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">IEx Console</h1>
        <a href="/admin" class="text-sm text-blue-600 hover:underline">← Admin</a>
      </div>

      <details class="border border-gray-200 rounded">
        <summary class="px-4 py-2 text-sm font-semibold cursor-pointer text-gray-700 select-none">
          Available aliases &amp; imports
        </summary>
        <div class="px-4 pb-4 pt-2 grid grid-cols-2 gap-x-8 gap-y-3 text-sm font-mono">
          <%= for {group, names} <- @context do %>
            <div>
              <div class="text-xs text-gray-400 uppercase tracking-wide mb-1">{group}</div>
              <%= for name <- names do %>
                <div class="text-gray-700">{name}</div>
              <% end %>
            </div>
          <% end %>
        </div>
      </details>

      <form phx-submit="eval">
        <textarea
          id="console-input"
          name="code"
          rows="5"
          phx-hook="ConsoleInput"
          class="w-full font-mono text-sm border border-gray-300 rounded p-3 focus:outline-none focus:ring-2 focus:ring-blue-500"
          placeholder="Repo.all(Game) |> length()"
        ><%= @code %></textarea>
        <div class="flex items-center gap-4 mt-2">
          <button
            type="submit"
            class="bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700 text-sm"
          >
            Run <span class="text-blue-200 text-xs ml-1">⌘↵</span>
          </button>
          <%= if @bindings != [] do %>
            <span class="text-xs text-gray-500 font-mono">
              bound: {Enum.map_join(@bindings, ", ", fn {k, _} -> to_string(k) end)}
            </span>
          <% end %>
          <%= if @history != [] do %>
            <button
              type="button"
              phx-click="clear"
              class="ml-auto text-xs text-gray-400 hover:text-gray-600"
            >
              Clear
            </button>
          <% end %>
        </div>
      </form>

      <%= for %{code: code, result: result} <- @history do %>
        <div class="border border-gray-200 rounded overflow-hidden text-sm font-mono">
          <div class="bg-gray-50 px-3 py-2 text-gray-800 whitespace-pre-wrap border-b border-gray-200">
            {code}
          </div>
          <div class={[
            "px-3 py-2 whitespace-pre-wrap break-all",
            if(match?({:ok, _}, result),
              do: "text-green-800 bg-green-50",
              else: "text-red-800 bg-red-50"
            )
          ]}>
            {elem(result, 1)}
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
