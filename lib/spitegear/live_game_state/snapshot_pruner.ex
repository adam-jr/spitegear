defmodule Spitegear.LiveGameState.SnapshotPruner do
  @moduledoc """
  Quantum job that deletes `WargearViewScreenDb` and `WargearHistoryApiResponseDb`
  rows older than 90 days. Runs daily at 2am.
  """

  alias Spitegear.LiveGameState.HistoryResponses
  alias Spitegear.LiveGameState.ViewScreens

  require Logger

  @days 90

  def run do
    {vs_count, _} = ViewScreens.prune(@days)
    {hr_count, _} = HistoryResponses.prune(@days)
    Logger.info("#{__MODULE__} pruned #{vs_count} view screen(s) and #{hr_count} history response(s) older than #{@days} days")
  end
end
