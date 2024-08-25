defmodule SpitegearWeb.SleeperController do
  use SpitegearWeb, :controller

  require Logger

  def handle_draft_pick(conn, draft_pick) do
    Logger.info(inspect(draft_pick))
    json(conn, :ok)
  end
end
