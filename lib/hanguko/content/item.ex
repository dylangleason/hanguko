defmodule Hanguko.Content.Item do
  @moduledoc """
  A single piece of study content: a Hangeul letter, a word, a phrase or a
  sentence. Per-user flashcards are generated from items.

  `source_key` (`"<deck-slug>/<key>"`) is the stable identity used by the
  importer, so that edits to an item keep users' review history intact.
  `meaning` may list alternative answers separated by `;`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @kinds [:jamo, :syllable, :word, :phrase, :sentence]

  schema "items" do
    field :source_key, :string
    field :kind, Ecto.Enum, values: @kinds
    field :korean, :string
    field :romanization, :string
    field :meaning, :string
    field :part_of_speech, :string
    field :hint, :string
    field :notes, :string
    field :tags, {:array, :string}, default: []
    field :position, :integer
    field :metadata, :map, default: %{}
    field :cloze, :string
    field :retired, :boolean, default: false

    belongs_to :deck, Hanguko.Content.Deck
    belongs_to :grammar_point, Hanguko.Content.GrammarPoint

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds

  @doc false
  def import_changeset(item, attrs) do
    item
    |> cast(attrs, [
      :source_key,
      :kind,
      :korean,
      :romanization,
      :meaning,
      :part_of_speech,
      :hint,
      :notes,
      :tags,
      :position,
      :metadata,
      :cloze,
      :retired
    ])
    # An empty `tags:` or `metadata:` in a content pack means "none", not NULL.
    |> update_change(:tags, &(&1 || []))
    |> update_change(:metadata, &(&1 || %{}))
    |> validate_required([:source_key, :kind, :korean, :meaning, :position])
    |> validate_format(:korean, ~r/\p{Hangul}/u, message: "must contain Hangul")
    |> validate_cloze()
    |> unique_constraint(:source_key)
  end

  # A sentence is studied by blanking out the grammar it demonstrates, so the
  # cloze has to be text that actually appears in the sentence.
  defp validate_cloze(changeset) do
    korean = get_field(changeset, :korean) || ""

    validate_change(changeset, :cloze, fn :cloze, cloze ->
      if String.contains?(korean, cloze),
        do: [],
        else: [cloze: "#{inspect(cloze)} does not appear in #{inspect(korean)}"]
    end)
  end

  @doc """
  The Korean text to pronounce for this item. Letters on their own are read
  out by their names, so jamo use an example syllable (가, 아) instead.
  """
  def speech_text(%__MODULE__{kind: :jamo, metadata: %{"example_syllable" => syllable}}),
    do: syllable

  def speech_text(%__MODULE__{korean: korean}), do: korean

  @doc """
  Splits a sentence around the grammar it demonstrates, as
  `{before, target, after}`. Returns `nil` when the item has no cloze.
  """
  def cloze_parts(%__MODULE__{cloze: nil}), do: nil

  def cloze_parts(%__MODULE__{cloze: cloze, korean: korean}) do
    case String.split(korean, cloze, parts: 2) do
      [before, rest] -> {before, cloze, rest}
      _ -> nil
    end
  end

  @doc "The accepted meanings, split on `;`."
  def meanings(%__MODULE__{meaning: meaning}) do
    meaning |> String.split(";") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end
end
