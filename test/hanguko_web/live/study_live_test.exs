defmodule HangukoWeb.StudyLiveTest do
  use HangukoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Hanguko.ContentFixtures
  import Hanguko.SRSFixtures

  alias Hanguko.Accounts.Scope
  alias Hanguko.Repo
  alias Hanguko.SRS
  alias Hanguko.SRS.Card

  test "requires logging in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/study")
  end

  describe "logged in" do
    setup :register_and_log_in_user

    setup %{user: user} do
      scope = Scope.for_user(user)
      deck = deck_fixture(title: "Food")
      SRS.enroll_deck(scope, deck)

      apple =
        item_fixture(deck, position: 1, korean: "사과", meaning: "apple", romanization: "sagwa")

      water = item_fixture(deck, position: 2, korean: "물", meaning: "water", romanization: "mul")

      %{scope: scope, deck: deck, apple: apple, water: water}
    end

    defp rate(view, rating) do
      key = view |> element("#study") |> render() |> data_key()
      render_hook(view, "rate", %{"rating" => to_string(rating), "key" => key})
    end

    defp data_key(html) do
      [key] = html |> LazyHTML.from_fragment() |> LazyHTML.attribute("data-key")
      key
    end

    test "shows a card, reveals the answer and moves on after rating", %{
      conn: conn,
      user: user,
      apple: apple
    } do
      {:ok, view, _html} = live(conn, ~p"/study")

      assert has_element?(view, "#card-front", "사과")
      assert has_element?(view, "#card-deck", "Food")
      assert has_element?(view, "#count-new", "2")
      refute has_element?(view, "#card-answer")
      refute has_element?(view, "#rating-buttons")

      view |> element("#show-answer") |> render_click()
      assert has_element?(view, "#card-answer", "apple")
      assert has_element?(view, "#card-answer", "sagwa")
      # New card intervals: Again 1m, Good 10m
      assert has_element?(view, "#rate-1", "1m")
      assert has_element?(view, "#rate-3", "10m")

      view |> element("#rate-3") |> render_click()

      assert has_element?(view, "#card-front", "물")
      assert has_element?(view, "#undo")

      assert %Card{state: :learning, template: :recognition} =
               Repo.get_by!(Card, user_id: user.id, item_id: apple.id)
    end

    test "ignores ratings before the answer is shown or for another card", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/study")
      key = view |> element("#study") |> render() |> data_key()

      render_hook(view, "rate", %{"rating" => "3", "key" => key})
      assert has_element?(view, "#card-front", "사과")

      render_hook(view, "flip", %{})
      render_hook(view, "rate", %{"rating" => "3", "key" => "0-recognition"})
      render_hook(view, "rate", %{"rating" => "9", "key" => key})
      assert has_element?(view, "#card-front", "사과")
      assert Repo.aggregate(Card, :count) == 0
      assert Repo.get_by(Card, user_id: user.id) == nil
    end

    test "undo brings back the previous card", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/study")
      render_hook(view, "flip", %{})
      rate(view, 1)
      assert has_element?(view, "#card-front", "물")

      view |> element("#undo") |> render_click()

      assert has_element?(view, "#card-front", "사과")
      refute has_element?(view, "#card-answer")
      refute has_element?(view, "#undo")
      assert Repo.get_by(Card, user_id: user.id) == nil
    end

    test "undo takes the rating out of the session stats", %{conn: conn, scope: scope} do
      {:ok, _} = SRS.update_settings(scope, %{daily_new_limit: 1})
      {:ok, view, _html} = live(conn, ~p"/study")

      render_hook(view, "flip", %{})
      rate(view, 1)
      view |> element("#undo") |> render_click()
      render_hook(view, "flip", %{})
      rate(view, 4)

      assert has_element?(view, "#session-stats", "Cards 1")
      assert has_element?(view, "#session-stats", "100%")
    end

    test "shows a summary when the session is done", %{conn: conn, scope: scope} do
      {:ok, _} = SRS.update_settings(scope, %{daily_new_limit: 1})
      {:ok, view, _html} = live(conn, ~p"/study")

      render_hook(view, "flip", %{})
      # Easy graduates the card straight to review, so nothing is left today.
      rate(view, 4)

      assert has_element?(view, "#session-done", "Nice work!")
      assert has_element?(view, "#session-stats", "100%")
      refute has_element?(view, "#flashcard")
    end

    test "explains when the daily new-card limit stops a session", %{conn: conn, scope: scope} do
      {:ok, _} = SRS.update_settings(scope, %{daily_new_limit: 1})
      {:ok, view, _html} = live(conn, ~p"/study")
      render_hook(view, "flip", %{})
      rate(view, 4)

      assert has_element?(view, "#session-done", "Nice work!")
      assert has_element?(view, "#limit-notice-new", "limit of 1 new card")
      assert has_element?(view, "#limit-notice a[href='/study/settings']")
      refute has_element?(view, "#limit-notice-review")

      # Studying another deck once the shared limit is used up
      phrases = deck_fixture(slug: "phrases", title: "Phrases", kind: :phrases)
      SRS.enroll_deck(scope, phrases)
      item_fixture(phrases, korean: "안녕하세요", kind: :phrase)

      {:ok, view, _html} = live(conn, ~p"/study?deck=phrases")
      assert has_element?(view, "#session-done", "Daily limit reached")
      assert has_element?(view, "#limit-notice-new")
    end

    test "recall cards show the meaning first", %{
      conn: conn,
      user: user,
      apple: apple,
      water: water
    } do
      two_days_ago = DateTime.add(DateTime.utc_now(:second), -2, :day)

      card_fixture(user, apple,
        introduced_at: two_days_ago,
        due: DateTime.add(two_days_ago, 30, :day)
      )

      card_fixture(user, water,
        introduced_at: two_days_ago,
        due: DateTime.add(two_days_ago, 30, :day)
      )

      {:ok, view, _html} = live(conn, ~p"/study")

      assert has_element?(view, "#flashcard", "How do you say this in Korean?")
      assert has_element?(view, "#card-front", "apple")
      refute has_element?(view, "#card-front", "사과")

      render_hook(view, "flip", %{})
      assert has_element?(view, "#card-answer", "사과")
      assert has_element?(view, "#card-answer [data-primary-speak][data-text='사과']")
    end

    test "can study a single deck", %{conn: conn, scope: scope} do
      places = deck_fixture(slug: "places", title: "Places", position: 99)
      SRS.enroll_deck(scope, places)
      item_fixture(places, korean: "집", meaning: "house")

      {:ok, view, _html} = live(conn, ~p"/study?deck=places")

      assert has_element?(view, "#card-front", "집")
      assert has_element?(view, "#count-new", "1")
      assert has_element?(view, "#end-session", "Places")
    end

    test "asks users without decks to pick some", %{conn: conn, scope: scope, deck: deck} do
      SRS.unenroll_deck(scope, deck)
      {:ok, view, _html} = live(conn, ~p"/study")

      assert has_element?(view, "#session-done a[href='/decks']")
    end
  end
end
