defmodule Hanguko.Content.Item do
  @moduledoc """
  A single piece of study content: a Hangeul letter, a word, a phrase or a
  sentence. Per-user flashcards are generated from items.

  `source_key` (`"<deck-slug>/<key>"`) is the stable identity used by the
  importer, so that edits to an item keep users' review history intact.
  `meaning` may list alternative answers separated by `;`.

  `metadata` carries what only some kinds need. Letters have `name` and
  `example_syllable`; phrases have `politeness` (one of
  `politeness_levels/0`, checked on import), and optionally `context`,
  `literal` and `variant_of` — the source key of the same phrase at another
  speech level.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @kinds [:jamo, :syllable, :word, :phrase, :sentence]
  @politeness_levels ~w(formal polite casual)

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
    |> validate_politeness()
    |> unique_constraint(:source_key)
  end

  @doc "The speech levels a phrase's `metadata.politeness` may name, most formal first."
  def politeness_levels, do: @politeness_levels

  # Badges, filters and study cards all key off the level, so a typo in a
  # pack would silently drop a phrase from every one of them.
  defp validate_politeness(changeset) do
    case get_field(changeset, :metadata) do
      %{"politeness" => level} when not is_nil(level) and level not in @politeness_levels ->
        add_error(
          changeset,
          :metadata,
          "politeness #{inspect(level)} is not one of #{Enum.join(@politeness_levels, ", ")}"
        )

      _ ->
        changeset
    end
  end

  # A sentence is studied by blanking out the grammar it demonstrates, so the
  # cloze has to appear in the sentence exactly once: twice would leave it
  # ambiguous which one the blank stands for. Checked against the final
  # values, so that editing only `korean` can't leave a stale cloze behind.
  defp validate_cloze(changeset) do
    korean = get_field(changeset, :korean) || ""

    case get_field(changeset, :cloze) do
      nil ->
        changeset

      "" ->
        add_error(changeset, :cloze, "can't be blank")

      cloze ->
        case length(String.split(korean, cloze)) - 1 do
          1 ->
            changeset

          0 ->
            add_error(
              changeset,
              :cloze,
              "#{inspect(cloze)} does not appear in #{inspect(korean)}"
            )

          count ->
            add_error(
              changeset,
              :cloze,
              "#{inspect(cloze)} appears #{count} times in #{inspect(korean)}, " <>
                "so the blank would be ambiguous"
            )
        end
    end
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
