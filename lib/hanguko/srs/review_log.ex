defmodule Hanguko.SRS.ReviewLog do
  @moduledoc """
  One review of a card. Records the card's scheduling state before the
  review (so the review can be undone) and after it.
  """
  use Ecto.Schema

  alias Hanguko.SRS.Card

  schema "review_logs" do
    field :rating, :integer
    field :reviewed_at, :utc_datetime
    field :duration_ms, :integer
    field :elapsed_days, :integer
    field :scheduled_seconds, :integer

    field :state_before, Ecto.Enum, values: Card.states()
    field :step_before, :integer
    field :stability_before, :float
    field :difficulty_before, :float
    field :due_before, :utc_datetime
    field :last_review_before, :utc_datetime

    field :state_after, Ecto.Enum, values: Card.states()
    field :stability_after, :float
    field :difficulty_after, :float

    belongs_to :user, Hanguko.Accounts.User
    belongs_to :card, Card

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "True if this was the card's first review (it was new)."
  def first_review?(%__MODULE__{state_before: state}), do: is_nil(state)
end
