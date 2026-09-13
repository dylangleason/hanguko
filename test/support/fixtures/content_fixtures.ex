defmodule Hanguko.ContentFixtures do
  @moduledoc """
  Test helpers for creating decks and items directly, without YAML packs.
  """

  alias Hanguko.Repo
  alias Hanguko.Content.{Deck, GrammarPoint, Item}

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

  def grammar_point_fixture(attrs \\ %{}) do
    n = System.unique_integer([:positive])

    %GrammarPoint{}
    |> GrammarPoint.import_changeset(
      Enum.into(attrs, %{
        slug: "point-#{n}",
        title: "-고 싶다",
        pattern: "동사 어간 + 고 싶어요",
        explanation: "Attach **-고 싶어요** to a verb stem.",
        level: 1,
        position: n
      })
    )
    |> Repo.insert!()
  end

  @doc """
  An example sentence for `point`: a sentence item in `deck` whose cloze is
  the grammar being taught.
  """
  def example_fixture(%Deck{} = deck, %GrammarPoint{} = point, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        korean: "한국에 가고 싶어요.",
        meaning: "I want to go to Korea.",
        kind: :sentence,
        cloze: "고 싶어요"
      })

    # A point belongs to the deck its examples live in, as the importer sets it.
    point |> Ecto.Changeset.change(deck_id: point.deck_id || deck.id) |> Repo.update!()

    deck
    |> item_fixture(attrs)
    |> Ecto.Changeset.change(grammar_point_id: point.id)
    |> Repo.update!()
  end

  def item_fixture(%Deck{} = deck, attrs \\ %{}) do
    n = System.unique_integer([:positive])
    attrs = Enum.into(attrs, %{korean: "사과", meaning: "apple", kind: :word, position: n})

    %Item{deck_id: deck.id}
    |> Item.import_changeset(Map.put_new(attrs, :source_key, "#{deck.slug}/#{n}"))
    |> Repo.insert!()
  end
end
