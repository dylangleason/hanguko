defmodule Hanguko.SRS.DeckEnrollment do
  @moduledoc """
  Marks a deck as one the user is studying. New cards are only introduced
  from enrolled decks.
  """
  use Ecto.Schema

  schema "deck_enrollments" do
    belongs_to :user, Hanguko.Accounts.User
    belongs_to :deck, Hanguko.Content.Deck

    timestamps(type: :utc_datetime)
  end
end
