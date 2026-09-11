defmodule Hanguko.ContentTest do
  use Hanguko.DataCase, async: true

  import Hanguko.ContentFixtures

  alias Hanguko.Content
  alias Hanguko.Content.Item

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
  end
end
