defmodule HangukoWeb.PageControllerTest do
  use HangukoWeb.ConnCase

  test "GET / shows the landing page", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ "Learn Korean, one card at a time."
    assert html =~ ~s(id="cta-register")
  end

  test "GET / hides sign-up prompts from logged-in users", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})
    html = conn |> get(~p"/") |> html_response(200)

    refute html =~ ~s(id="cta-register")
    assert html =~ ~s(id="nav-log-out")
  end
end
