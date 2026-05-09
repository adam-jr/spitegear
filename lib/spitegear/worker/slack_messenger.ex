defmodule Spitegear.Worker.SlackMessenger do
  @moduledoc false
  use GenServer
  require Logger

  alias Spitegear.Slack.API
  alias Spitegear.Slack.Message

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(_opts) do
    Logger.info("Initializing #{__MODULE__}")

    Phoenix.PubSub.subscribe(Spitegear.PubSub, "slack_messages")

    {:ok, nil}
  end

  def dm(recipient, text) do
    send(self(), {:dm, recipient, text})
  end

  def msg(channel, text) do
    send(self(), {:message, channel, text})
  end

  def handle_info({:ssl_closed, _}, state) do
    {:noreply, state}
  end

  def handle_info({:dm, recipient, text}, state) do
    API.post_dm(text, recipient)
    {:noreply, state}
  end

  def handle_info({:message, channel, [type: type, payload: payload]}, state) do
    text = Message.text(type, payload)
    API.post_message(text, channel)
    {:noreply, state}
  end

  def handle_info({:message, channel, text}, state) do
    API.post_message(text, channel)
    {:noreply, state}
  end
end
