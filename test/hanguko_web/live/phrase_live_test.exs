defmodule HangukoWeb.PhraseLiveTest do
  use HangukoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Hanguko.ContentFixtures

  alias Hanguko.SRS

  setup do
    greetings =
      deck_fixture(
        kind: :phrases,
        slug: "pl-greetings",
        title: "Greetings",
        title_ko: "인사",
        position: 1
      )

    restaurant =
      deck_fixture(kind: :phrases, slug: "pl-restaurant", title: "Restaurant", position: 2)

    food = deck_fixture(kind: :vocab, slug: "pl-food", title: "Food")
    item_fixture(food, korean: "사과", meaning: "apple")

    polite =
      item_fixture(greetings,
        kind: :phrase,
        position: 1,
        korean: "잘 지냈어요?",
        romanization: "jal jinaesseoyo",
        meaning: "how have you been?",
        metadata: %{
          "politeness" => "polite",
          "context" => "Meeting someone you haven't seen for a while."
        }
      )

    casual =
      item_fixture(greetings,
        kind: :phrase,
        position: 2,
        korean: "잘 지냈어?",
        meaning: "how have you been?",
        metadata: %{"politeness" => "casual", "variant_of" => polite.source_key}
      )

    formal =
      item_fixture(greetings,
        kind: :phrase,
        position: 3,
        korean: "안녕하십니까",
        meaning: "hello",
        metadata: %{"politeness" => "formal", "literal" => "Are you at peace?"}
      )

    order =
      item_fixture(restaurant,
        kind: :phrase,
        korean: "이거 주세요",
        meaning: "I'll have this, please",
        metadata: %{"politeness" => "polite"}
      )

    %{
      greetings: greetings,
      restaurant: restaurant,
      polite: polite,
      casual: casual,
      formal: formal,
      order: order
    }
  end

  test "shows the first situation with each phrase's speech level and details", %{
    conn: conn,
    polite: polite,
    casual: casual,
    formal: formal,
    order: order
  } do
    {:ok, view, _html} = live(conn, ~p"/phrases")

    assert has_element?(view, "#situation-pl-greetings[aria-current='page']")
    assert has_element?(view, "#situation-pl-restaurant")
    refute has_element?(view, "#situation-pl-food")
    assert has_element?(view, "#situation h2", "Greetings")

    assert has_element?(view, "#phrases-#{polite.id}", "잘 지냈어요?")
    assert has_element?(view, "#phrases-#{polite.id}", "jal jinaesseoyo")
    assert has_element?(view, "#phrases-#{polite.id}", "Polite")
    assert has_element?(view, "#phrases-#{polite.id}", "haven't seen for a while")
    assert has_element?(view, "#phrases-#{polite.id}-speak[data-text='잘 지냈어요?']")
    assert has_element?(view, "#phrases-#{formal.id}", "Are you at peace?")
    refute has_element?(view, "#phrases-#{order.id}")

    # Variants are linked one way in the packs but shown from both sides.
    assert has_element?(view, "#phrases-#{polite.id}-variant-#{casual.id}", "잘 지냈어?")
    assert has_element?(view, "#phrases-#{casual.id}-variant-#{polite.id}", "잘 지냈어요?")
    refute has_element?(view, "#phrases-#{formal.id} [id*='-variant-']")
  end

  test "switches situation and filters by speech level", %{
    conn: conn,
    polite: polite,
    casual: casual,
    order: order
  } do
    {:ok, view, _html} = live(conn, ~p"/phrases")

    view |> element("#politeness-casual") |> render_click()
    assert_patch(view, ~p"/phrases?#{[situation: "pl-greetings", politeness: "casual"]}")
    assert has_element?(view, "#phrases-#{casual.id}")
    refute has_element?(view, "#phrases-#{polite.id}")

    # The speech level stays selected when moving to another situation.
    view |> element("#situation-pl-restaurant") |> render_click()
    assert_patch(view, ~p"/phrases?#{[situation: "pl-restaurant", politeness: "casual"]}")
    refute has_element?(view, "#phrases-#{order.id}")

    view |> element("#politeness-all") |> render_click()
    assert_patch(view, ~p"/phrases?#{[situation: "pl-restaurant"]}")
    assert has_element?(view, "#phrases-#{order.id}", "이거 주세요")
  end

  test "falls back to the first situation and all levels for unknown params", %{
    conn: conn,
    polite: polite,
    casual: casual
  } do
    {:ok, view, _html} = live(conn, ~p"/phrases?situation=nowhere&politeness=rude")

    assert has_element?(view, "#situation-pl-greetings[aria-current='page']")
    assert has_element?(view, "#politeness-all[aria-current='page']")
    assert has_element?(view, "#phrases-#{polite.id}")
    assert has_element?(view, "#phrases-#{casual.id}")
  end

  test "asks anonymous visitors to log in to study", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/phrases")

    assert has_element?(view, "#enroll[href='/users/log-in']")
    refute has_element?(view, "#study-situation")
  end

  describe "logged in" do
    setup :register_and_log_in_user

    test "adds a situation to the learner's studies and removes it", %{
      conn: conn,
      scope: scope,
      greetings: greetings,
      restaurant: restaurant
    } do
      {:ok, view, _html} = live(conn, ~p"/phrases")
      refute has_element?(view, "#studying-pl-greetings")

      view |> element("#enroll") |> render_click()

      assert SRS.enrolled?(scope, greetings)
      refute SRS.enrolled?(scope, restaurant)
      assert has_element?(view, "#studying-pl-greetings")
      assert has_element?(view, "#study-situation[href='/study?deck=pl-greetings']")

      view |> element("#enroll") |> render_click()

      refute SRS.enrolled?(scope, greetings)
      refute has_element?(view, "#studying-pl-greetings")
      refute has_element?(view, "#study-situation")
    end
  end
end
