defmodule Spitegear.Worker.KeepAlive do
  use GenServer

  @interval :timer.seconds(5)

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_ping()
    {:ok, state}
  end

  def handle_info(:ping, state) do
    ping_self()
    schedule_ping()
    {:noreply, state}
  end

  defp schedule_ping do
    Process.send_after(self(), :ping, @interval)
  end

  defp ping_self do
    _ = Finch.start_link(name: :keep_alive)

    url = URI.encode("https://spitegear.fly.dev/ping")
    # url = URI.encode("http://localhost:4000/ping")

    Finch.build(:get, url)
    |> Finch.request(:keep_alive)
  end
end
