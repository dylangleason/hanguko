defmodule HangukoWeb.PageControllerTest do
  use HangukoWeb.ConnCase

  test "GET / shows the landing page", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ "Learn Korean, one card at a time."
    assert html =~ ~s(id="cta-register")
  end

  test "GET / sends logged-in users to their dashboard", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})
    assert conn |> get(~p"/") |> redirected_to() == ~p"/dashboard"
  end
end
