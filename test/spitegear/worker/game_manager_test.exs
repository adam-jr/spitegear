defmodule Spitegear.Worker.GameManagerTest do
  # async: false — these tests run real GenServers that hit the DB from a
  # different process, so the sandbox is put in shared mode (see DataCase).
  use Spitegear.DataCase, async: false

  alias Spitegear.HTML.Player
  alias Spitegear.LiveGameState.Turn
  alias Spitegear.LiveGameState.Turns
  alias Spitegear.Repo
  alias Spitegear.Wargear.HTTP.ViewScreen, as: HTTPViewScreen
  alias Spitegear.Worker.GameManager

  @game_id "11111"

  defp player(name) do
    %Player{
      name: name,
      slack_name: "@#{name}",
      eliminated?: false,
      winner?: false,
      current_turn?: true
    }
  end

  defp view_screen(current_player_name) do
    %HTTPViewScreen{
      game_id: @game_id,
      url: URI.parse("https://www.wargear.net/games/view/#{@game_id}"),
      game_name: "Test Game",
      board_name: "Classic",
      created: "2024-01-01",
      finished: nil,
      current_player: player(current_player_name),
      players: [player(current_player_name)],
      eliminated: [],
      winners: [],
      fogged?: true
    }
  end

  defp insert_open_turn(reminded_at) do
    Repo.insert!(%Turn{
      game_id: @game_id,
      player_name: "adam",
      started_at: reminded_at,
      reminded_at: reminded_at,
      reminders: 0
    })
  end

  defp start_manager(total_fog) do
    name = :"game_manager_test_#{System.unique_integer([:positive])}"
    {:ok, pid} = GameManager.start_link(game_id: @game_id, total_fog: total_fog, name: name)
    pid
  end

  describe "view_screen_fetched with total_fog: false" do
    test "never sends a reminder, no matter how overdue the open turn is" do
      way_overdue =
        DateTime.utc_now() |> DateTime.add(-30 * 24 * 60 * 60) |> DateTime.truncate(:second)

      insert_open_turn(way_overdue)

      Phoenix.PubSub.subscribe(Spitegear.PubSub, "slack_messages")
      pid = start_manager(false)

      GenServer.cast(pid, {:view_screen_fetched, view_screen("adam")})
      # Let the cast (and its DB writes) land before asserting nothing arrived.
      :sys.get_state(pid)

      refute_receive {:message, _, _, _}, 200
      assert Turns.get_open_turn(@game_id).reminders == 0
    end
  end

  describe "view_screen_fetched with total_fog: true" do
    test "is a no-op for a turn that isn't due for a reminder yet" do
      just_started = DateTime.utc_now() |> DateTime.truncate(:second)
      insert_open_turn(just_started)

      Phoenix.PubSub.subscribe(Spitegear.PubSub, "slack_messages")
      pid = start_manager(true)

      GenServer.cast(pid, {:view_screen_fetched, view_screen("adam")})
      :sys.get_state(pid)

      refute_receive {:message, _, _, _}, 200
      assert Turns.get_open_turn(@game_id).reminders == 0
    end
  end
end
