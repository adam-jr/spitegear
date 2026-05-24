defmodule SpitegearWeb.PageControllerTest do
  use SpitegearWeb.ConnCase

  test "GET / renders landing page", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Spitegear"
    assert html_response(conn, 200) =~ "wargear.net"
  end
end
