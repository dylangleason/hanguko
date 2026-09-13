defmodule Hanguko.Content.PacksTest do
  @moduledoc """
  Sanity checks on the curated content in priv/content.
  """
  use Hanguko.DataCase, async: true

  alias Hanguko.{Content, Korean}
  alias Hanguko.Content.{Importer, Item}
  alias Hanguko.SRS.Card

  setup do
    assert {:ok, stats} = Importer.import_dir()
    %{stats: stats}
  end

  test "all packs import cleanly and idempotently", %{stats: stats} do
    assert stats.items.created > 0
    assert {:ok, %{items: %{created: 0, updated: 0, retired: 0}}} = Importer.import_dir()
  end

  test "Hangeul decks cover all 40 letters" do
    letters =
      for deck <- Content.list_decks_with_items(:hangeul), item <- deck.items, do: item.korean

    assert length(letters) == 40
    assert Enum.uniq(letters) == letters

    # Every letter can be placed in the syllable builder.
    for letter <- letters do
      assert letter in Korean.initials() or letter in Korean.medials(), letter
    end
  end

  test "letters have what the Hangeul chart displays" do
    for deck <- Content.list_decks_with_items(:hangeul), item <- deck.items do
      assert item.kind == :jamo
      assert item.romanization, item.korean

      for key <- ~w(name example_syllable example_word example_meaning) do
        assert is_binary(item.metadata[key]), "#{item.korean} is missing #{key}"
      end

      assert String.contains?(item.metadata["example_word"], item.korean) or
               item.korean in Korean.to_jamo(item.metadata["example_word"]),
             "#{item.metadata["example_word"]} does not use #{item.korean}"
    end
  end

  test "grammar points explain a pattern and come with example sentences" do
    points = Content.list_grammar_points()
    assert length(points) >= 12

    for point <- points do
      point = Content.get_grammar_point_by_slug!(nil, point.slug)
      assert point.summary, "#{point.slug} has no summary"
      assert length(point.items) >= 3, "#{point.slug} needs more examples"

      for row <- point.formation do
        assert row["when"] != nil and row["form"] != nil, point.slug
      end

      for item <- point.items do
        assert item.kind == :sentence
        assert item.cloze, "#{item.korean} has no cloze"
        # The blank has to fall on the grammar being taught, which is the
        # first place the cloze text appears in the sentence.
        assert {before, cloze, _rest} = Item.cloze_parts(item)
        assert cloze == item.cloze
        refute String.contains?(before, item.cloze)
      end
    end
  end

  test "grammar lessons run in curriculum order, level by level" do
    points = Content.list_grammar_points()
    levels = Enum.map(points, & &1.level)

    assert levels == Enum.sort(levels)
    assert Enum.uniq(levels) == [1, 2]
    assert hd(points).slug == "ieyo-yeyo"

    # A lesson takes its level from the pack it belongs to, and the lessons
    # of one pack stay together.
    deck_ids = Enum.map(points, & &1.deck_id)
    refute nil in deck_ids
    assert Enum.uniq(deck_ids) == Enum.dedup(deck_ids)
  end

  test "every example sentence is studied as a cloze card" do
    for point <- Content.list_grammar_points(),
        item <- Content.get_grammar_point_by_slug!(nil, point.slug).items do
      assert Card.templates_for(item) == [:cloze], item.korean
    end
  end

  test "vocabulary and phrases have romanization and valid politeness levels" do
    for kind <- [:vocab, :phrases],
        deck <- Content.list_decks_with_items(kind),
        item <- deck.items do
      assert item.romanization, "#{deck.slug}/#{item.korean} has no romanization"
      assert item.metadata["politeness"] in [nil, "formal", "polite", "casual"]
    end
  end
end
