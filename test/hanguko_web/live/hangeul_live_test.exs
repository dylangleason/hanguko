defmodule HangukoWeb.HangeulLiveTest do
  use HangukoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Hanguko.ContentFixtures

  setup do
    deck = deck_fixture(kind: :hangeul, slug: "hangeul-consonants", title: "Basic consonants")

    giyeok =
      item_fixture(deck,
        korean: "ㄱ",
        kind: :jamo,
        meaning: "g",
        romanization: "g / k",
        metadata: %{"name" => "기역", "example_syllable" => "가"}
      )

    vowels = deck_fixture(kind: :hangeul, slug: "hangeul-vowels", title: "Basic vowels")
    o = item_fixture(vowels, korean: "ㅗ", kind: :jamo, meaning: "o", romanization: "o")

    %{giyeok: giyeok, o: o}
  end

  defp syllable(view), do: view |> element("#builder-syllable") |> render() |> text()

  defp text(html), do: html |> LazyHTML.from_fragment() |> LazyHTML.text() |> String.trim()

  test "shows letter charts from the Hangeul decks", %{conn: conn, giyeok: giyeok} do
    {:ok, view, _html} = live(conn, ~p"/hangeul")

    assert has_element?(view, "#chart-hangeul-consonants")
    assert has_element?(view, "#chart-hangeul-vowels")
    assert has_element?(view, "#jamo-#{giyeok.id}", "기역")
    assert has_element?(view, "#jamo-#{giyeok.id}-speak[data-text='가']")
  end

  test "builds syllables from the pickers", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/hangeul")
    assert syllable(view) == "한"

    view |> element("#picker-initial button[phx-value-jamo='ㄱ']") |> render_click()
    assert syllable(view) == "간"

    view |> element("#picker-final button[phx-value-jamo='']") |> render_click()
    assert syllable(view) == "가"

    view |> element("#picker-final button[phx-value-jamo='ㅇ']") |> render_click()
    assert syllable(view) == "강"
    assert has_element?(view, "#builder-speak[data-text='강']")
    assert has_element?(view, "#builder-result", "gang")
  end

  test "clicking a chart letter fills the matching slot", %{conn: conn, giyeok: giyeok, o: o} do
    {:ok, view, _html} = live(conn, ~p"/hangeul")

    view |> element("#jamo-#{giyeok.id} button[phx-click='pick']") |> render_click()
    view |> element("#jamo-#{o.id} button[phx-click='pick']") |> render_click()

    assert syllable(view) == "곤"
    assert has_element?(view, "#jamo-#{giyeok.id} button[aria-pressed='true']")
  end

  test "random always produces a valid syllable", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/hangeul")

    for _ <- 1..5 do
      view |> element("#builder-random") |> render_click()
      assert Hanguko.Korean.syllable?(syllable(view))
    end
  end

  test "takes words apart", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/hangeul")

    view |> form("#analyze-form", analyze: %{text: "닭 a"}) |> render_change()

    assert has_element?(view, "#analysis-0", "ㄷ ㅏ ㄺ")
    assert has_element?(view, "#analysis-0", "dak")
    assert has_element?(view, "#analysis-1", "a")
    refute has_element?(view, "#analysis-2")
  end
end
