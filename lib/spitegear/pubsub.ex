defmodule Spitegear.PubSub do
  @moduledoc false
  alias Phoenix.PubSub

  def dm(recipient, text),
    do: PubSub.broadcast(__MODULE__, "slack_messages", {:dm, recipient, text})

  def msg(channel, text),
    do: PubSub.broadcast(__MODULE__, "slack_messages", {:message, channel, text})
end
