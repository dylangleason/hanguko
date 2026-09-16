defmodule HangukoWeb.StatsLiveTest do
  use HangukoWeb.ConnCase, async: true

  import Hanguko.ContentFixtures
  import Hanguko.SRSFixtures

  alias Hanguko.SRS

  test "requires logging in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/stats")
  end

  describe "logged in" do
    setup :register_and_log_in_user

    test "invites a learner without history to start studying", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/stats")

      assert has_element?(view, "#no-progress a[href='/dashboard']")
      refute has_element?(view, "#stats")
      refute has_element?(view, "#activity")
    end

    test "shows the streak, recent totals, activity and what's coming due", %{
      conn: conn,
      user: user,
      scope: scope
    } do
      now = DateTime.utc_now(:second)
      # Keep the study day's rollover twelve hours away from now, so the
      # reviews below can't straddle two study days.
      {:ok, _} = SRS.update_settings(scope, %{day_rollover_hour: rem(now.hour + 12, 24)})

      deck = deck_fixture()
      SRS.enroll_deck(scope, deck)
      card = card_fixture(user, item_fixture(deck), due: DateTime.add(now, 2, :day))
      card_fixture(user, item_fixture(deck), stability: 30.0, due: DateTime.add(now, 60, :day))

      review_log_fixture(user, card, DateTime.add(now, -60), rating: 3, duration_ms: 120_000)
      review_log_fixture(user, card, DateTime.add(now, -120), rating: 1, duration_ms: 60_000)

      {:ok, view, _html} = live(conn, ~p"/stats")

      assert has_element?(view, "#stat-streak", "1 day")
      assert has_element?(view, "#stat-reviews", "2")
      assert has_element?(view, "#stat-retention", "50%")
      assert has_element?(view, "#stat-retention", "1 of 2 reviews remembered")
      assert has_element?(view, "#stat-time", "3 min")

      assert has_element?(view, "#activity-grid [title^='2 reviews']")
      assert has_element?(view, "#activity-table td", "2")

      assert has_element?(view, "#forecast-chart [title^='1 card due']")
      assert has_element?(view, "#forecast-peak", "1")
      assert has_element?(view, "#forecast-table td", "1")

      assert has_element?(view, "#cards-young", "1")
      assert has_element?(view, "#cards-mature", "1")
      assert has_element?(view, "#cards-by-state", "2 in all")
    end

    test "says when nothing is coming due", %{conn: conn, user: user, scope: scope} do
      deck = deck_fixture()
      SRS.enroll_deck(scope, deck)

      card_fixture(user, item_fixture(deck),
        due: DateTime.add(DateTime.utc_now(:second), 90, :day)
      )

      {:ok, view, _html} = live(conn, ~p"/stats")

      assert has_element?(view, "#forecast-empty")
      refute has_element?(view, "#forecast-chart")
    end
  end
end
