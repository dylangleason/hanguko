defmodule Hanguko.SRS.Card do
  @moduledoc """
  A user's flashcard: one study direction (template) of a content item, with
  its FSRS scheduling state.

  Cards are created lazily, the first time the user reviews them.

  Templates:

    * `:recognition` - see the Korean, recall the meaning (for letters: the sound)
    * `:recall` - see the meaning, produce the Korean
    * `:cloze` - see a sentence with its grammar blanked out, fill in the gap
  """
  use Ecto.Schema

  alias Hanguko.Content.Item

  @type t :: %__MODULE__{}

  @templates [:recognition, :recall, :cloze]
  @states [:learning, :review, :relearning]

  # A card forgotten this many times is a leech: it keeps coming back without
  # being learned, so `Hanguko.SRS.review_card/5` suspends it instead of
  # letting it crowd out the rest of the day's reviews.
  @leech_lapses 8

  schema "cards" do
    field :template, Ecto.Enum, values: @templates
    field :state, Ecto.Enum, values: @states
    field :step, :integer
    field :stability, :float
    field :difficulty, :float
    field :due, :utc_datetime
    field :last_review_at, :utc_datetime
    field :reps, :integer, default: 0
    field :lapses, :integer, default: 0
    field :suspended, :boolean, default: false
    field :introduced_at, :utc_datetime

    belongs_to :user, Hanguko.Accounts.User
    belongs_to :item, Item

    timestamps(type: :utc_datetime)
  end

  def templates, do: @templates
  def states, do: @states

  @doc "How many lapses make a card a leech."
  def leech_lapses, do: @leech_lapses

  @doc """
  True if the card has lapsed often enough to count as a leech.

  It is derived from `lapses` rather than stored in a column of its own, so
  unsuspending a leech to try again doesn't stop it being flagged as one.
  """
  def leech?(%__MODULE__{lapses: lapses}), do: lapses >= @leech_lapses

  @doc """
  The templates studied for an item, in the order they are introduced.
  Letters are only studied in the recognition direction, and example
  sentences only as cloze deletions of the grammar they demonstrate.
  """
  def templates_for(%Item{kind: :jamo}), do: [:recognition]
  def templates_for(%Item{kind: kind}) when kind in [:word, :phrase], do: [:recognition, :recall]
  def templates_for(%Item{kind: :sentence, cloze: cloze}) when is_binary(cloze), do: [:cloze]
  def templates_for(%Item{}), do: []
end
