defmodule Spitegear.Worker.GamePollerTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Spitegear.Worker.GamePoller

  describe "jitter/1" do
    test "stays within +/-15% of the input" do
      for ms <- [1_000, 60_000, :timer.hours(24)] do
        spread = trunc(ms * 0.15)

        for _ <- 1..200 do
          result = GamePoller.jitter(ms)
          assert result in (ms - spread)..(ms + spread)
        end
      end
    end

    test "produces varying results across calls" do
      results = for _ <- 1..50, do: GamePoller.jitter(60_000)
      assert Enum.uniq(results) |> length() > 1
    end
  end
end
