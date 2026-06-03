defmodule Spitegear.LiveGameState.TurnsTest do
  use Spitegear.DataCase, async: true

  alias Spitegear.LiveGameState.Turn
  alias Spitegear.LiveGameState.Turns
  alias Spitegear.Repo

  @base ~U[2024-01-01 12:00:00Z]

  defp insert_turn(attrs \\ []) do
    Repo.insert!(%Turn{
      game_id: Keyword.get(attrs, :game_id, "11111"),
      player_name: Keyword.get(attrs, :player_name, "adam"),
      started_at: Keyword.get(attrs, :started_at, @base),
      ended_at: Keyword.get(attrs, :ended_at, DateTime.add(@base, 3600))
    })
  end

  describe "list_turns/1" do
    test "returns empty list when no turns exist for the game" do
      assert Turns.list_turns("11111") == []
    end

    test "returns turns for the given game_id" do
      insert_turn()
      [turn] = Turns.list_turns("11111")
      assert turn.game_id == "11111"
      assert turn.player_name == "adam"
    end

    test "does not return turns belonging to other games" do
      insert_turn(game_id: "99999")
      assert Turns.list_turns("11111") == []
    end

    test "returns multiple turns ordered chronologically by started_at" do
      second = DateTime.add(@base, 3600)
      third = DateTime.add(@base, 7200)

      insert_turn(player_name: "charlie", started_at: third)
      insert_turn(player_name: "adam", started_at: @base)
      insert_turn(player_name: "bob", started_at: second)

      names = Turns.list_turns("11111") |> Enum.map(& &1.player_name)
      assert names == ["adam", "bob", "charlie"]
    end

    test "returns all turn fields" do
      reminded = DateTime.add(@base, 1800)

      Repo.insert!(%Turn{
        game_id: "11111",
        player_name: "adam",
        started_at: @base,
        ended_at: DateTime.add(@base, 3600),
        reminded: reminded,
        reminders: 2,
        moving_announced: true
      })

      [turn] = Turns.list_turns("11111")
      assert turn.reminded == reminded
      assert turn.reminders == 2
      assert turn.moving_announced == true
    end
  end
end
