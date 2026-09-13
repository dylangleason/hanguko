defmodule Hanguko.Content.GrammarPoint do
  @moduledoc """
  One grammar pattern taught as a lesson, e.g. `-아요/어요`.

  Like decks, grammar points are global curriculum loaded from
  `priv/content` by `Hanguko.Content.Importer`; the slug is their identity.

  A point belongs to the deck its example sentences live in, which is also
  what places it in the curriculum.

  `formation` lists the shapes the pattern takes, each a map with `"when"`,
  `"form"` and an optional `"example"` — for instance "after a consonant"
  takes `이에요`, as in `학생이에요`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "grammar_points" do
    field :slug, :string
    field :title, :string
    field :pattern, :string
    field :summary, :string
    field :level, :integer, default: 1
    field :position, :integer, default: 0
    field :explanation, :string
    field :formation, {:array, :map}, default: []
    field :retired, :boolean, default: false

    field :learned_at, :utc_datetime, virtual: true

    belongs_to :deck, Hanguko.Content.Deck
    has_many :items, Hanguko.Content.Item

    timestamps(type: :utc_datetime)
  end

  @doc "True once the learner has marked this point as learned."
  def learned?(%__MODULE__{learned_at: learned_at}), do: not is_nil(learned_at)

  @doc false
  def import_changeset(point, attrs) do
    point
    |> cast(attrs, [
      :slug,
      :title,
      :pattern,
      :summary,
      :level,
      :position,
      :explanation,
      :formation,
      :retired
    ])
    |> update_change(:formation, &(&1 || []))
    |> validate_required([:slug, :title, :pattern, :level, :position, :explanation])
    |> validate_format(:slug, ~r/^[a-z0-9]+(-[a-z0-9]+)*$/,
      message: "must be lowercase words separated by dashes"
    )
    |> validate_number(:level, greater_than: 0)
    |> validate_formation()
    |> unique_constraint(:slug)
  end

  defp validate_formation(changeset) do
    validate_change(changeset, :formation, fn :formation, rows ->
      if Enum.all?(rows, &(is_map(&1) and Map.has_key?(&1, "when") and Map.has_key?(&1, "form"))),
        do: [],
        else: [formation: "each row needs `when` and `form`"]
    end)
  end
end
