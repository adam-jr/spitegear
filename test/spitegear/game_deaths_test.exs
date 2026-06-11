defmodule Spitegear.GameDeathsTest do
  use Spitegear.DataCase, async: true

  alias Spitegear.GameDeath
  alias Spitegear.GameDeaths
  alias Spitegear.Repo

  @base ~U[2024-01-01 12:00:00Z]

  describe "create/4" do
    test "inserts a game_death record" do
      assert {:ok, death} = GameDeaths.create("11111", "adam", @base)
      assert death.game_id == "11111"
      assert death.player_name == "adam"
      assert death.eliminated_at == @base
      assert death.inferred == false
    end

    test "records inferred: true when passed" do
      assert {:ok, death} = GameDeaths.create("11111", "adam", @base, inferred: true)
      assert death.inferred == true
    end

    test "is idempotent — second insert is a no-op" do
      {:ok, _} = GameDeaths.create("11111", "adam", @base)
      {:ok, _} = GameDeaths.create("11111", "adam", @base)
      assert Repo.aggregate(GameDeath, :count) == 1
    end
  end

  describe "list/1" do
    test "returns empty list when no deaths exist" do
      assert GameDeaths.list("11111") == []
    end

    test "returns all deaths for the given game" do
      {:ok, _} = GameDeaths.create("11111", "adam", @base)
      {:ok, _} = GameDeaths.create("11111", "bob", @base)
      assert length(GameDeaths.list("11111")) == 2
    end

    test "does not return deaths for other games" do
      {:ok, _} = GameDeaths.create("99999", "adam", @base)
      assert GameDeaths.list("11111") == []
    end
  end
end
