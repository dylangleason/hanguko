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
    refute has_element?(view, "#account-menu-button")
    refute has_element?(view, "#mobile-nav-log-out")
    refute has_element?(view, "#nav-study")
  end

  test "logged-in users get account links in the account menu and the mobile menu", %{
    conn: conn
  } do
    %{conn: conn, user: user} = register_and_log_in_user(%{conn: conn})
    {:ok, view, _html} = live(conn, ~p"/hangeul")

    for id <- ~w(study cards progress) do
      assert has_element?(view, "#nav-#{id}")
      assert has_element?(view, "#mobile-menu #mobile-nav-#{id}")
    end

    assert has_element?(view, "#account-menu-button[aria-controls='account-menu']")

    for id <- ~w(settings study-settings log-out) do
      assert has_element?(view, "#account-menu #nav-#{id}")
      assert has_element?(view, "#mobile-menu #mobile-nav-#{id}")
    end

    assert has_element?(view, "#account-menu", user.email)
    assert has_element?(view, "#nav-study-settings[href='/study/settings']")
    assert has_element?(view, "#mobile-nav-settings", user.email)
    refute has_element?(view, "#nav-log-in")
    refute has_element?(view, "#mobile-nav-log-in")
  end

  describe "the current section" do
    test "is marked in both menus, and follows live navigation", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/hangeul")

      assert has_element?(view, "#nav-hangeul[aria-current='page']")
      assert has_element?(view, "#mobile-nav-hangeul[aria-current='page']")
      refute has_element?(view, "#nav-grammar[aria-current]")

      {:ok, view, _html} =
        view |> element("#nav-grammar") |> render_click() |> follow_redirect(conn)

      assert has_element?(view, "#nav-grammar[aria-current='page']")
      refute has_element?(view, "#nav-hangeul[aria-current]")
    end

    test "covers a section's inner pages", %{conn: conn} do
      conn = register_and_log_in_user(%{conn: conn}).conn

      for {path, id} <- [
            {~p"/decks?kind=vocab", "vocab"},
            {~p"/study/settings", "study"},
            {~p"/dashboard", "study"},
            {~p"/stats", "progress"},
            {~p"/cards", "cards"}
          ] do
        {:ok, view, _html} = live(conn, path)

        assert has_element?(view, "#nav-#{id}[aria-current='page']"), "#{path} should mark #{id}"

        assert [_] =
                 view
                 |> render()
                 |> LazyHTML.from_document()
                 |> LazyHTML.query("#site-header nav [aria-current]")
                 |> Enum.to_list()
      end
    end

    test "on deck pages follows the kind of deck, not the path", %{conn: conn} do
      deck = Hanguko.ContentFixtures.deck_fixture(%{slug: "nav-letters", kind: :hangeul})

      for path <- [~p"/decks/#{deck.slug}", ~p"/decks?kind=hangeul"] do
        {:ok, view, _html} = live(conn, path)

        assert has_element?(view, "#nav-hangeul[aria-current='page']"),
               "#{path} should mark hangeul"

        refute has_element?(view, "#nav-vocab[aria-current]")
      end

      {:ok, view, _html} = live(conn, ~p"/decks")
      refute has_element?(view, "#site-header [aria-current]")
    end

    test "is not marked on pages outside the sections", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/log-in")

      refute has_element?(view, "#site-header [aria-current]")
    end
  end
end
