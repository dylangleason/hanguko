defmodule Hanguko.Content.Deck do
  @moduledoc """
  A themed collection of study items, e.g. "Basic consonants" or "Food".

  Decks are global curriculum content loaded from `priv/content` by
  `Hanguko.Content.Importer`; the slug is their stable identity.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @kinds [:hangeul, :vocab, :phrases, :sentences]

  schema "decks" do
    field :slug, :string
    field :title, :string
    field :title_ko, :string
    field :kind, Ecto.Enum, values: @kinds
    field :level, :integer, default: 1
    field :position, :integer, default: 0
    field :description, :string
    field :retired, :boolean, default: false
    field :item_count, :integer, virtual: true

    has_many :items, Hanguko.Content.Item

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds

  @doc false
  def import_changeset(deck, attrs) do
    deck
    |> cast(attrs, [:slug, :title, :title_ko, :kind, :level, :position, :description, :retired])
    |> validate_required([:slug, :title, :kind, :level, :position])
    |> validate_format(:slug, ~r/^[a-z0-9]+(-[a-z0-9]+)*$/,
      message: "must be lowercase words separated by dashes"
    )
    |> validate_number(:level, greater_than: 0)
    |> unique_constraint(:slug)
  end
end
