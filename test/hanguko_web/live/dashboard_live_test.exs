defmodule HangukoWeb.DashboardLiveTest do
  use HangukoWeb.ConnCase, async: true

  import Hanguko.ContentFixtures
  import Hanguko.SRSFixtures

  alias Hanguko.Accounts.Scope
  alias Hanguko.SRS

  test "requires logging in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/dashboard")
  end

  describe "logged in" do
    setup :register_and_log_in_user

    test "suggests decks to users who aren't studying any", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      assert has_element?(view, "#no-decks")
      assert has_element?(view, "#all-caught-up")
      refute has_element?(view, "#study-now")
    end

    test "shows today's work per deck", %{conn: conn, user: user} do
      scope = Scope.for_user(user)
      deck = deck_fixture(slug: "food", title: "Food")
      SRS.enroll_deck(scope, deck)
      apple = item_fixture(deck, position: 1)
      item_fixture(deck, position: 2)
      card_fixture(user, apple, due: DateTime.add(DateTime.utc_now(:second), -60))

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      assert has_element?(view, "#today-due", "1")
      assert has_element?(view, "#today-new", "1")
      assert has_element?(view, "#study-now[href='/study']")
      assert has_element?(view, "#deck-#{deck.id}", "Food")
      assert has_element?(view, "#study-deck-#{deck.id}[href='/study?deck=food']")
      refute has_element?(view, "#limit-notice")
    end

    test "explains when today's new-card limit is used up", %{conn: conn, user: user} do
      scope = Scope.for_user(user)
      deck = deck_fixture()
      SRS.enroll_deck(scope, deck)
      learned = item_fixture(deck, position: 1)
      item_fixture(deck, position: 2)
      {:ok, _} = SRS.update_settings(scope, %{daily_new_limit: 1})
      now = DateTime.utc_now(:second)
      card_fixture(user, learned, introduced_at: now, due: DateTime.add(now, 3, :day))

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      assert has_element?(view, "#today-new", "0")
      assert has_element?(view, "#limit-notice-new", "limit of 1 new card")
    end

    test "remembers the browser's time zone", %{conn: conn, user: user} do
      conn = put_connect_params(conn, %{"timezone" => "Asia/Seoul"})
      {:ok, _view, _html} = live(conn, ~p"/dashboard")

      assert SRS.get_settings(Scope.for_user(user)).timezone == "Asia/Seoul"
    end
  end
end
