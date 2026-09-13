defmodule Hanguko.ContentTest do
  use Hanguko.DataCase, async: true

  import Hanguko.ContentFixtures

  alias Hanguko.Content
  alias Hanguko.Content.{GrammarPoint, Item}
  alias Hanguko.SRS.Card

  describe "list_decks/1" do
    test "orders decks, counts active items and hides retired decks" do
      phrases = deck_fixture(kind: :phrases, position: 1)
      food = deck_fixture(kind: :vocab, position: 2)
      numbers = deck_fixture(kind: :vocab, position: 1)
      _retired = deck_fixture(kind: :vocab, retired: true)
      item_fixture(food)
      item_fixture(food)
      item_fixture(food, retired: true)

      assert [n, f, p] = Content.list_decks()
      assert [n.id, f.id, p.id] == [numbers.id, food.id, phrases.id]
      assert f.item_count == 2
      assert n.item_count == 0

      assert [%{id: id}] = Content.list_decks(kind: :phrases)
      assert id == phrases.id
    end
  end

  test "get_deck!/1 includes the item count" do
    deck = deck_fixture()
    item_fixture(deck)

    assert %{item_count: 1} = Content.get_deck!(deck.id)
    assert_raise Ecto.NoResultsError, fn -> Content.get_deck!(deck_fixture(retired: true).id) end
  end

  test "get_deck_by_slug!/1 preloads active items in order" do
    deck = deck_fixture()
    second = item_fixture(deck, position: 2, korean: "물")
    first = item_fixture(deck, position: 1)
    item_fixture(deck, position: 3, retired: true)

    assert %{items: items} = Content.get_deck_by_slug!(deck.slug)
    assert Enum.map(items, & &1.id) == [first.id, second.id]
    assert_raise Ecto.NoResultsError, fn -> Content.get_deck_by_slug!("missing") end
  end

  test "list_decks_with_items/1 returns decks of one kind with their items" do
    deck = deck_fixture(kind: :hangeul)
    item_fixture(deck, korean: "ㄱ", kind: :jamo)
    deck_fixture(kind: :vocab)

    assert [%{id: id, items: [%Item{korean: "ㄱ"}]}] = Content.list_decks_with_items(:hangeul)
    assert id == deck.id
  end

  describe "Item" do
    test "speech_text/1 uses the example syllable for letters" do
      assert Item.speech_text(%Item{
               kind: :jamo,
               korean: "ㄱ",
               metadata: %{"example_syllable" => "가"}
             }) ==
               "가"

      assert Item.speech_text(%Item{kind: :word, korean: "사과", metadata: %{}}) == "사과"
    end

    test "meanings/1 splits alternatives" do
      assert Item.meanings(%Item{meaning: "to go; go ;"}) == ["to go", "go"]
    end

    test "the cloze has to appear in the sentence exactly once" do
      changeset = fn attrs ->
        Item.import_changeset(
          %Item{},
          Enum.into(attrs, %{
            source_key: "grammar/1",
            kind: :sentence,
            korean: "한국에 가고 싶어요.",
            meaning: "I want to go to Korea.",
            position: 1
          })
        )
      end

      assert changeset.(%{cloze: "고 싶어요"}).valid?
      assert changeset.(%{}).valid?

      # An empty `cloze:` in a pack means "none", like tags and metadata, so
      # the sentence simply isn't studied as a cloze card.
      empty = changeset.(%{cloze: ""})
      assert empty.valid?
      assert Ecto.Changeset.apply_changes(empty).cloze == nil
      assert Card.templates_for(Ecto.Changeset.apply_changes(empty)) == []

      # A blank left on a record is still an error, rather than a card whose
      # blank stands for nothing.
      assert %{cloze: ["can't be blank"]} =
               errors_on(Item.import_changeset(%Item{cloze: ""}, %{korean: "한국에 가고 싶어요."}))

      assert %{cloze: [missing]} = errors_on(changeset.(%{cloze: "고 있어요"}))
      assert missing =~ "does not appear in"

      assert %{cloze: [ambiguous]} =
               errors_on(changeset.(%{korean: "학교에 가고 집에 가고 싶어요.", cloze: "가고"}))

      assert ambiguous =~ "appears 2 times"
    end

    test "editing only the sentence still checks the cloze" do
      item = %Item{
        source_key: "grammar/1",
        kind: :sentence,
        korean: "한국에 가고 싶어요.",
        meaning: "I want to go to Korea.",
        cloze: "고 싶어요",
        position: 1
      }

      changeset = Item.import_changeset(item, %{korean: "저는 학생이에요.", cloze: "고 싶어요"})

      refute changeset.valid?
      assert %{cloze: [message]} = errors_on(changeset)
      assert message =~ "does not appear in"
    end

    test "cloze_parts/1 splits a sentence around its grammar" do
      item = %Item{korean: "한국에 가고 싶어요.", cloze: "고 싶어요"}
      assert Item.cloze_parts(item) == {"한국에 가", "고 싶어요", "."}

      assert Item.cloze_parts(%Item{korean: "사과", cloze: nil}) == nil
      assert Item.cloze_parts(%Item{korean: "사과", cloze: "배"}) == nil
    end
  end

  describe "grammar" do
    setup do
      %{scope: Hanguko.AccountsFixtures.user_scope_fixture()}
    end

    test "lists active points in curriculum order", %{scope: scope} do
      second = grammar_point_fixture(level: 1, position: 2)
      first = grammar_point_fixture(level: 1, position: 1)
      later = grammar_point_fixture(level: 2, position: 1)
      retired = grammar_point_fixture(retired: true)

      ids = Enum.map(Content.list_grammar_points(scope), & &1.id)
      assert ids == [first.id, second.id, later.id]
      refute retired.id in ids
    end

    test "marks a point as learned, once", %{scope: scope} do
      point = grammar_point_fixture()
      deck = deck_fixture(kind: :sentences)
      example_fixture(deck, point)

      refute GrammarPoint.learned?(Content.get_grammar_point_by_slug!(scope, point.slug))
      assert Content.learned_grammar_point_ids(scope) == MapSet.new()

      {:ok, _} = Content.mark_grammar_learned(scope, point, ~U[2026-09-13 09:00:00Z])
      {:ok, _} = Content.mark_grammar_learned(scope, point)

      loaded = Content.get_grammar_point_by_slug!(scope, point.slug)
      assert GrammarPoint.learned?(loaded)
      assert loaded.learned_at == ~U[2026-09-13 09:00:00Z]
      assert Content.learned_grammar_point_ids(scope) == MapSet.new([point.id])
      assert [%Item{cloze: "고 싶어요"}] = loaded.items

      {:ok, 1} = Content.unmark_grammar_learned(scope, point)
      refute GrammarPoint.learned?(Content.get_grammar_point_by_slug!(scope, point.slug))
    end

    test "anonymous visitors have learned nothing" do
      point = grammar_point_fixture()

      refute GrammarPoint.learned?(Content.get_grammar_point_by_slug!(nil, point.slug))
      assert Content.learned_grammar_point_ids(nil) == MapSet.new()
    end

    test "one user's progress doesn't show up for another", %{scope: scope} do
      point = grammar_point_fixture()
      other = Hanguko.AccountsFixtures.user_scope_fixture()
      {:ok, _} = Content.mark_grammar_learned(other, point)

      refute GrammarPoint.learned?(Content.get_grammar_point_by_slug!(scope, point.slug))
    end
  end
end
