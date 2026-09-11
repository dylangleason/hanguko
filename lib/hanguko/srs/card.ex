defmodule Hanguko.SRS.Card do
  @moduledoc """
  A user's flashcard: one study direction (template) of a content item, with
  its FSRS scheduling state.

  Cards are created lazily, the first time the user reviews them.

  Templates:

    * `:recognition` - see the Korean, recall the meaning (for letters: the sound)
    * `:recall` - see the meaning, produce the Korean
  """
  use Ecto.Schema

  alias Hanguko.Content.Item

  @templates [:recognition, :recall]
  @states [:learning, :review, :relearning]

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

  @doc """
  The templates studied for an item, in the order they are introduced.
  Letters are only studied in the recognition direction.
  """
  def templates_for(%Item{kind: :jamo}), do: [:recognition]
  def templates_for(%Item{kind: kind}) when kind in [:word, :phrase], do: [:recognition, :recall]
  def templates_for(%Item{}), do: []
end
