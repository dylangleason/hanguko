defmodule Hanguko.ContentFixtures do
  @moduledoc """
  Test helpers for creating decks and items directly, without YAML packs.
  """

  alias Hanguko.Repo
  alias Hanguko.Content.{Deck, Item}

  def deck_fixture(attrs \\ %{}) do
    n = System.unique_integer([:positive])

    %Deck{}
    |> Deck.import_changeset(
      Enum.into(attrs, %{
        slug: "deck-#{n}",
        title: "Deck #{n}",
        kind: :vocab,
        level: 1,
        position: n
      })
    )
    |> Repo.insert!()
  end

  def item_fixture(%Deck{} = deck, attrs \\ %{}) do
    n = System.unique_integer([:positive])
    attrs = Enum.into(attrs, %{korean: "사과", meaning: "apple", kind: :word, position: n})

    %Item{deck_id: deck.id}
    |> Item.import_changeset(Map.put_new(attrs, :source_key, "#{deck.slug}/#{n}"))
    |> Repo.insert!()
  end
end
