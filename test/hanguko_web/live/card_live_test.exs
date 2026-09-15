defmodule HangukoWeb.CardLiveTest do
  use HangukoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Hanguko.AccountsFixtures
  import Hanguko.ContentFixtures
  import Hanguko.SRSFixtures

  alias Hanguko.Repo
  alias Hanguko.SRS
  alias Hanguko.SRS.Card

  test "requires logging in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/cards")
  end

  describe "logged in" do
    setup :register_and_log_in_user

    setup %{user: user} do
      food = deck_fixture(%{slug: "cards-food", title: "Food", position: 1})
      verbs = deck_fixture(%{slug: "cards-verbs", title: "Verbs", position: 2})

      water = item_fixture(food, %{korean: "물", meaning: "water", romanization: "mul"})
      eat = item_fixture(verbs, %{korean: "먹다", meaning: "to eat", romanization: "meokda"})

      %{
        food: food,
        water: card_fixture(user, water),
        eat: card_fixture(user, eat, template: :recall)
      }
    end

    test "lists the learner's cards with their deck", %{conn: conn, water: water, eat: eat} do
      {:ok, view, _html} = live(conn, ~p"/cards")

      assert has_element?(view, "#cards-#{water.id}", "물")
      assert has_element?(view, "#cards-#{water.id} a[href='/decks/cards-food']")
      assert has_element?(view, "#cards-#{eat.id}", "Recall")
      assert has_element?(view, "#card-count", "2 cards")
    end

    test "doesn't list another learner's cards", %{conn: conn} do
      other = card_fixture(user_fixture(), item_fixture(deck_fixture()))

      {:ok, view, _html} = live(conn, ~p"/cards")

      refute has_element?(view, "#cards-#{other.id}")
    end

    test "searches, and keeps the search in the URL", %{conn: conn, water: water, eat: eat} do
      {:ok, view, _html} = live(conn, ~p"/cards")

      view |> form("#card-filters", filter: %{query: "water"}) |> render_change()

      assert_patched(view, ~p"/cards?query=water")
      assert has_element?(view, "#cards-#{water.id}")
      refute has_element?(view, "#cards-#{eat.id}")
      assert has_element?(view, "#card-count", "1 card")
    end

    test "filters by deck", %{conn: conn, food: food, water: water, eat: eat} do
      {:ok, view, _html} = live(conn, ~p"/cards")

      view |> form("#card-filters", filter: %{deck: food.slug}) |> render_change()

      assert_patched(view, ~p"/cards?deck=cards-food")
      assert has_element?(view, "#cards-#{water.id}")
      refute has_element?(view, "#cards-#{eat.id}")
    end

    test "suspends a card and puts it back", %{conn: conn, water: water} do
      {:ok, view, _html} = live(conn, ~p"/cards")

      view |> element("#suspend-#{water.id}") |> render_click()

      assert has_element?(view, "#suspended-#{water.id}")
      assert has_element?(view, "#unsuspend-#{water.id}")
      assert Repo.get!(Card, water.id).suspended

      view |> element("#unsuspend-#{water.id}") |> render_click()

      refute has_element?(view, "#suspended-#{water.id}")
      refute Repo.get!(Card, water.id).suspended
    end

    test "a card that no longer matches the filter leaves the list", %{
      conn: conn,
      scope: scope,
      water: water
    } do
      {:ok, _} = SRS.suspend_card(scope, water.id)

      {:ok, view, _html} = live(conn, ~p"/cards?status=suspended")
      assert has_element?(view, "#cards-#{water.id}")

      view |> element("#unsuspend-#{water.id}") |> render_click()

      refute has_element?(view, "#cards-#{water.id}")
      assert has_element?(view, "#card-count", "No cards match")
    end

    test "resets a card", %{conn: conn, water: water} do
      {:ok, view, _html} = live(conn, ~p"/cards")

      html = view |> element("#reset-#{water.id}") |> render_click()

      assert html =~ "Card reset"
      assert %Card{state: :learning, reps: 0, lapses: 0} = Repo.get!(Card, water.id)
    end

    test "flags leeches and filters down to them", %{
      conn: conn,
      user: user,
      food: food,
      water: water
    } do
      leech = card_fixture(user, item_fixture(food), lapses: Card.leech_lapses())

      {:ok, view, _html} = live(conn, ~p"/cards")
      assert has_element?(view, "#leech-#{leech.id}")

      {:ok, view, _html} = live(conn, ~p"/cards?status=leech")

      assert has_element?(view, "#status-leech[aria-current='page']")
      assert has_element?(view, "#cards-#{leech.id}")
      refute has_element?(view, "#cards-#{water.id}")
    end

    test "says so when a learner has no cards at all" do
      # A second learner, so the cards made in setup aren't theirs.
      conn = register_and_log_in_user(%{conn: Phoenix.ConnTest.build_conn()}).conn

      {:ok, view, _html} = live(conn, ~p"/cards")

      assert has_element?(view, "#card-count", "No cards match")
      assert has_element?(view, "#cards-empty")
    end
  end
end
