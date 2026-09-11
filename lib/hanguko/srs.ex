defmodule Hanguko.SRS do
  @moduledoc """
  Per-user study state: which decks a user is studying, and (from Phase 2)
  their flashcards and review history.
  """
  import Ecto.Query, warn: false

  alias Hanguko.Repo
  alias Hanguko.Accounts.Scope
  alias Hanguko.Content.Deck
  alias Hanguko.SRS.DeckEnrollment

  @doc """
  Returns the set of deck ids the scope's user is enrolled in. Anonymous
  visitors (a `nil` scope) are enrolled in nothing.
  """
  def enrolled_deck_ids(nil), do: MapSet.new()

  def enrolled_deck_ids(%Scope{user: user}) do
    DeckEnrollment
    |> where([e], e.user_id == ^user.id)
    |> select([e], e.deck_id)
    |> Repo.all()
    |> MapSet.new()
  end

  @doc "Returns true if the scope's user is enrolled in `deck`."
  def enrolled?(nil, _deck), do: false

  def enrolled?(%Scope{user: user}, %Deck{id: deck_id}) do
    Repo.exists?(from e in DeckEnrollment, where: e.user_id == ^user.id and e.deck_id == ^deck_id)
  end

  @doc "Enrolls the scope's user in `deck`. Enrolling twice is a no-op."
  def enroll_deck(%Scope{user: user}, %Deck{id: deck_id}) do
    Repo.insert(%DeckEnrollment{user_id: user.id, deck_id: deck_id},
      on_conflict: :nothing,
      conflict_target: [:user_id, :deck_id]
    )
  end

  @doc "Removes the scope's user from `deck`. Review history is kept."
  def unenroll_deck(%Scope{user: user}, %Deck{id: deck_id}) do
    {count, _} =
      Repo.delete_all(
        from e in DeckEnrollment, where: e.user_id == ^user.id and e.deck_id == ^deck_id
      )

    {:ok, count}
  end
end
