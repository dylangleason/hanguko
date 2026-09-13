defmodule Hanguko.Content.GrammarProgress do
  @moduledoc """
  Marks a grammar point as learned by a user, which unlocks the cloze cards
  of its example sentences.
  """
  use Ecto.Schema

  schema "grammar_progress" do
    field :learned_at, :utc_datetime

    belongs_to :user, Hanguko.Accounts.User
    belongs_to :grammar_point, Hanguko.Content.GrammarPoint

    timestamps(type: :utc_datetime)
  end
end
