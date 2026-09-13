defmodule HangukoWeb.NavigationTest do
  use HangukoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "anonymous visitors get section and log-in links in both menus", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/hangeul")

    assert has_element?(view, "#mobile-menu-button[aria-controls='mobile-menu']")

    for id <- ~w(hangeul vocab phrases log-in register) do
      assert has_element?(view, "#nav-#{id}")
      assert has_element?(view, "#mobile-menu #mobile-nav-#{id}")
    end

    assert has_element?(view, "#nav-phrases[href='/phrases']")
    refute has_element?(view, "#mobile-nav-log-out")
    refute has_element?(view, "#nav-study")
  end

  test "logged-in users get settings and log-out links in both menus", %{conn: conn} do
    %{conn: conn, user: user} = register_and_log_in_user(%{conn: conn})
    {:ok, view, _html} = live(conn, ~p"/hangeul")

    for id <- ~w(study settings log-out) do
      assert has_element?(view, "#nav-#{id}")
      assert has_element?(view, "#mobile-menu #mobile-nav-#{id}")
    end

    assert has_element?(view, "#mobile-nav-settings", user.email)
    refute has_element?(view, "#mobile-nav-log-in")
  end
end
