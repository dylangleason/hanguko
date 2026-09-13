defmodule HangukoWeb.GrammarLiveTest do
  use HangukoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Hanguko.ContentFixtures

  alias Hanguko.{Content, SRS}
  alias Hanguko.Accounts.Scope

  @particle_formation [
    %{"when" => "The noun ends in a consonant", "batchim" => true, "form" => "이에요"},
    %{"when" => "The noun ends in a vowel", "batchim" => false, "form" => "예요"}
  ]

  defp point_with_examples(attrs \\ []) do
    deck = deck_fixture(slug: "grammar-basics", title: "Sentence basics", kind: :sentences)

    point =
      grammar_point_fixture(
        Enum.into(attrs, %{
          slug: "ieyo-yeyo",
          title: "이에요 / 예요",
          pattern: "명사 + 이에요/예요",
          summary: "Saying what something is.",
          explanation: "Attach **이에요** to the noun.",
          formation: @particle_formation
        })
      )

    example =
      example_fixture(deck, point,
        korean: "저는 학생이에요.",
        meaning: "I am a student.",
        cloze: "이에요"
      )

    %{deck: deck, point: point, example: example}
  end

  describe "index" do
    test "lists lessons by level", %{conn: conn} do
      %{point: point} = point_with_examples()
      later = grammar_point_fixture(level: 2, slug: "but-jiman", title: "-지만")

      {:ok, view, _html} = live(conn, ~p"/grammar")

      assert has_element?(view, "#level-1")
      assert has_element?(view, "#grammar-#{point.id}", "이에요 / 예요")
      assert has_element?(view, "#grammar-#{point.id}", "Saying what something is.")
      assert has_element?(view, "#grammar-#{later.id} a[href='/grammar/but-jiman']")
      refute has_element?(view, "#learned-#{point.id}")
    end

    test "marks the lessons a learner has already learned", %{conn: conn} do
      %{point: point} = point_with_examples()
      user = Hanguko.AccountsFixtures.user_fixture()
      {:ok, _} = Content.mark_grammar_learned(Scope.for_user(user), point)

      {:ok, view, _html} = live(log_in_user(conn, user), ~p"/grammar")

      assert has_element?(view, "#learned-#{point.id}", "Learned")
    end
  end

  describe "show" do
    test "explains the pattern and shows its examples", %{conn: conn} do
      %{example: example} = point_with_examples()

      {:ok, view, _html} = live(conn, ~p"/grammar/ieyo-yeyo")

      assert has_element?(view, "#explanation strong", "이에요")
      assert has_element?(view, "#formation-0", "The noun ends in a consonant")
      assert has_element?(view, "#example-#{example.id}", "I am a student.")
      # The grammar itself is highlighted inside the sentence.
      assert has_element?(view, "#example-#{example.id} mark", "이에요")
      assert has_element?(view, "#example-speak-#{example.id}[data-text='저는 학생이에요.']")
    end

    test "the try-it box picks the form a word takes", %{conn: conn} do
      point_with_examples()
      {:ok, view, _html} = live(conn, ~p"/grammar/ieyo-yeyo")

      refute has_element?(view, "#try-answer")

      view |> form("#try-it", %{"word" => "학생"}) |> render_change()
      assert has_element?(view, "#try-answer", "학생이에요")
      assert has_element?(view, "#try-answer", "The noun ends in a consonant")

      view |> form("#try-it", %{"word" => "의사"}) |> render_change()
      assert has_element?(view, "#try-answer", "의사예요")

      view |> form("#try-it", %{"word" => "hello"}) |> render_change()
      assert has_element?(view, "#try-hint")
      refute has_element?(view, "#try-answer")
    end

    test "the try-it box writes a lone consonant into the last syllable", %{conn: conn} do
      point_with_examples(
        slug: "future-eul-geoyeyo",
        title: "-(으)ㄹ 거예요",
        formation: [
          %{"when" => "The stem ends in a vowel", "batchim" => false, "form" => "-ㄹ 거예요"},
          %{"when" => "The stem ends in a consonant", "batchim" => true, "form" => "-을 거예요"}
        ]
      )

      {:ok, view, _html} = live(conn, ~p"/grammar/future-eul-geoyeyo")

      view |> form("#try-it", %{"word" => "가"}) |> render_change()
      assert has_element?(view, "#try-answer", "갈 거예요")

      view |> form("#try-it", %{"word" => "먹"}) |> render_change()
      assert has_element?(view, "#try-answer", "먹을 거예요")
    end

    test "hides the try-it box when the form doesn't depend on batchim", %{conn: conn} do
      point_with_examples(
        slug: "and-go",
        formation: [%{"when" => "Any stem", "form" => "-고"}]
      )

      {:ok, view, _html} = live(conn, ~p"/grammar/and-go")

      assert has_element?(view, "#formation-0")
      refute has_element?(view, "#try-it")
    end

    test "marking a lesson learned starts studying its sentences", %{conn: conn} do
      %{deck: deck, point: point} = point_with_examples()
      user = Hanguko.AccountsFixtures.user_fixture()
      scope = Scope.for_user(user)

      {:ok, view, _html} = live(log_in_user(conn, user), ~p"/grammar/ieyo-yeyo")
      refute has_element?(view, "#learned-note")

      view |> element("#toggle-learned") |> render_click()

      assert has_element?(view, "#toggle-learned", "Learned")
      assert has_element?(view, "#study-grammar[href='/study?deck=grammar-basics']")
      assert Content.learned_grammar_point_ids(scope) == MapSet.new([point.id])
      # Its sentences are only studied from a deck the learner is studying.
      assert SRS.enrolled?(scope, deck)

      view |> element("#toggle-learned") |> render_click()

      assert has_element?(view, "#toggle-learned", "Mark as learned")
      refute has_element?(view, "#learned-note")
      assert Content.learned_grammar_point_ids(scope) == MapSet.new()
    end

    test "asks anonymous visitors to log in before marking a lesson", %{conn: conn} do
      point_with_examples()
      {:ok, view, _html} = live(conn, ~p"/grammar/ieyo-yeyo")

      assert {:error, {:live_redirect, %{to: "/users/log-in"}}} =
               view |> element("#toggle-learned") |> render_click()
    end
  end
end
