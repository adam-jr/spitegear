defmodule SpitegearWeb.AdminSessionController do
  use SpitegearWeb, :controller
  alias Spitegear.Accounts

  def new(conn, _params) do
    render(conn, :new, layout: {SpitegearWeb.Layouts, :root}, error: nil)
  end

  def create(conn, %{"username" => username, "password" => password}) do
    user = Accounts.get_user_by_username(username)

    if Accounts.verify_password(user, password) do
      conn
      |> put_session(:admin_logged_in, true)
      |> redirect(to: ~p"/admin")
    else
      render(conn, :new, layout: {SpitegearWeb.Layouts, :root}, error: "Invalid username or password.")
    end
  end

  def delete(conn, _params) do
    conn
    |> clear_session()
    |> redirect(to: ~p"/admin/login")
  end
end
