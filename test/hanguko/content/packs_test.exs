defmodule Hanguko.Content.PacksTest do
  @moduledoc """
  Sanity checks on the curated content in priv/content.
  """
  use Hanguko.DataCase, async: true

  alias Hanguko.{Content, Korean}
  alias Hanguko.Content.Importer

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

  test "vocabulary and phrases have romanization and valid politeness levels" do
    for kind <- [:vocab, :phrases],
        deck <- Content.list_decks_with_items(kind),
        item <- deck.items do
      assert item.romanization, "#{deck.slug}/#{item.korean} has no romanization"
      assert item.metadata["politeness"] in [nil, "formal", "polite", "casual"]
    end
  end
end
