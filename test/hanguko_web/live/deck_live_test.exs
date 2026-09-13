defmodule HangukoWeb.DeckLiveTest do
  use HangukoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Hanguko.ContentFixtures

  alias Hanguko.SRS

  setup do
    food = deck_fixture(kind: :vocab, slug: "food", title: "Food", title_ko: "음식")
    phrases = deck_fixture(kind: :phrases, slug: "essentials", title: "Survival phrases")

    apple = item_fixture(food, korean: "사과", meaning: "apple", romanization: "sagwa")

    hello =
      item_fixture(phrases,
        korean: "안녕하세요",
        kind: :phrase,
        meaning: "hello; hi",
        metadata: %{"politeness" => "polite", "literal" => "Are you at peace?"}
      )

    %{food: food, phrases: phrases, apple: apple, hello: hello}
  end

  describe "Index" do
    test "lists decks and filters by kind", %{conn: conn, food: food, phrases: phrases} do
      {:ok, view, _html} = live(conn, ~p"/decks")
      assert has_element?(view, "#decks-#{food.id}", "Food")
      assert has_element?(view, "#decks-#{phrases.id}", "Survival phrases")

      view |> element("#filter-phrases") |> render_click()
      assert_patch(view, ~p"/decks?kind=phrases")
      refute has_element?(view, "#decks-#{food.id}")
      assert has_element?(view, "#decks-#{phrases.id}")
    end

    test "leaves grammar sentence decks to the grammar lessons", %{conn: conn} do
      sentences = deck_fixture(kind: :sentences, title: "Sentence basics")

      {:ok, view, _html} = live(conn, ~p"/decks")
      refute has_element?(view, "#decks-#{sentences.id}")

      # Not even by asking for them directly.
      {:ok, view, _html} = live(conn, ~p"/decks?kind=sentences")
      refute has_element?(view, "#decks-#{sentences.id}")
    end

    test "asks anonymous visitors to log in to study", %{conn: conn, food: food} do
      {:ok, view, _html} = live(conn, ~p"/decks")
      assert has_element?(view, "a#enroll-#{food.id}[href='/users/log-in']")
    end

    test "enrolls and unenrolls the current user", %{conn: conn, food: food} do
      %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn}) |> with_scope()
      {:ok, view, _html} = live(conn, ~p"/decks")

      view |> element("#enroll-#{food.id}") |> render_click()
      assert has_element?(view, "#enroll-#{food.id}[aria-pressed='true']")
      assert SRS.enrolled?(scope, food)

      view |> element("#enroll-#{food.id}") |> render_click()
      assert has_element?(view, "#enroll-#{food.id}[aria-pressed='false']")
      refute SRS.enrolled?(scope, food)
    end
  end

  describe "Show" do
    test "lists the deck's items", %{conn: conn, phrases: phrases, hello: hello} do
      {:ok, view, _html} = live(conn, ~p"/decks/#{phrases.slug}")

      assert has_element?(view, "#items-#{hello.id}", "안녕하세요")
      assert has_element?(view, "#items-#{hello.id}", "hello, hi")
      assert has_element?(view, "#items-#{hello.id}", "Are you at peace?")
      assert has_element?(view, "#items-#{hello.id}", "해요체")
      assert has_element?(view, "#items-#{hello.id}-speak[data-text='안녕하세요']")
      assert has_element?(view, "#toggle-meaning")
    end

    test "enrolls the current user", %{conn: conn, food: food} do
      %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn}) |> with_scope()
      {:ok, view, _html} = live(conn, ~p"/decks/#{food.slug}")

      view |> element("#enroll") |> render_click()
      assert has_element?(view, "#enroll[aria-pressed='true']")
      assert SRS.enrolled?(scope, food)
    end

    test "returns 404 for unknown decks", %{conn: conn} do
      assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/decks/nope") end
    end
  end

  defp with_scope(%{user: user} = context),
    do: Map.put(context, :scope, Hanguko.Accounts.Scope.for_user(user))
end
