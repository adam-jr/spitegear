defmodule SpitegearWeb.Router do
  use SpitegearWeb, :router

  alias Spitegear.Accounts

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SpitegearWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :admin_auth do
    plug :require_admin_auth
  end

  scope "/", SpitegearWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/ping", PingController, :ping
  end

  scope "/admin", SpitegearWeb do
    pipe_through [:browser, :admin_auth]

    live "/", AdminLive
    live "/games", AdminGamesLive
    live "/games/:game_id", AdminGameShowLive
    live "/games/:game_id/log", AdminGameLogLive
    live "/logs", AdminLogsLive
    live "/templates", AdminTemplatesLive
    live "/games/:game_id/templates", AdminTemplatesLive
  end

  # Other scopes may use custom stacks.
  # scope "/api", SpitegearWeb do
  #   pipe_through :api
  # end

  scope "/api", SpitegearWeb do
    pipe_through :api
    post "/slack/events", SlackController, :handle_events
    post "/sleeper/draftpick", SleeperController, :handle_draft_pick
  end

  defp require_admin_auth(conn, _opts) do
    with ["Basic " <> encoded] <- Plug.Conn.get_req_header(conn, "authorization"),
         {:ok, decoded} <- Base.decode64(encoded),
         [username, password] <- String.split(decoded, ":", parts: 2),
         user <- Accounts.get_user_by_username(username),
         true <- Accounts.verify_password(user, password) do
      conn
    else
      _ ->
        conn
        |> Plug.Conn.put_resp_header("www-authenticate", ~s(Basic realm="Spitegear Admin"))
        |> Plug.Conn.send_resp(401, "Unauthorized")
        |> Plug.Conn.halt()
    end
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:spitegear, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: SpitegearWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
