defmodule HangukoWeb.Labels do
  @moduledoc """
  Human-readable names for the domain's fixed enums: `Hanguko.SRS.Card`
  templates and states, `Hanguko.Content.Item` politeness levels, and
  `Hanguko.Content.Deck` kinds. The enums themselves are defined in the
  domain layer; this is the one table the web layer adds on top, imported
  everywhere `CoreComponents` is so a page and its filters never name a
  value twice.
  """

  alias Hanguko.SRS.Card

  @doc "Card templates (`Card.templates/0`) paired with their labels."
  def templates, do: Enum.map(Card.templates(), &{&1, template_label(&1)})

  @doc "A label for a card template (`Card.templates/0`)."
  def template_label(:recognition), do: "Recognition"
  def template_label(:recall), do: "Recall"
  def template_label(:cloze), do: "Cloze"

  @doc "A label for a card state (`Card.states/0`)."
  def state_label(:learning), do: "Learning"
  def state_label(:review), do: "In review"
  def state_label(:relearning), do: "Relearning"

  @doc """
  A label for a phrase's speech level (`Item.politeness_levels/0`), or
  `nil` when `level` isn't one of them — used to hide a badge rather than
  show one with no text.
  """
  def politeness_label("formal"), do: "Formal"
  def politeness_label("polite"), do: "Polite"
  def politeness_label("casual"), do: "Casual"
  def politeness_label(_), do: nil

  @doc "A label for a deck kind (`Deck.kinds/0`)."
  def deck_kind_label(:hangeul), do: "Hangeul"
  def deck_kind_label(:vocab), do: "Vocabulary"
  def deck_kind_label(:phrases), do: "Phrases"
  def deck_kind_label(:sentences), do: "Sentences"
end
