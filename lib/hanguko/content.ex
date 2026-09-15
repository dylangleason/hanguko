defmodule Hanguko.Content do
  @moduledoc """
  The global curriculum: decks and their items. Content is read-only at
  runtime; it is maintained as YAML packs in `priv/content` and loaded with
  `mix hanguko.content.import`.

  Queries are built in `Hanguko.Content.Queries`.
  """
  alias Hanguko.Accounts.Scope
  alias Hanguko.Repo
  alias Hanguko.Content.{GrammarPoint, GrammarProgress, Queries}

  @doc """
  Lists active decks with `item_count` populated, in curriculum order: by
  kind (in the order of `Deck.kinds/0`), then level and position.

  ## Options

    * `:kind` - only return decks of this kind, or of any kind in this list
  """
  def list_decks(opts \\ []) do
    Queries.active_decks_with_item_counts()
    |> Queries.of_kind(opts[:kind])
    |> Queries.in_curriculum_order()
    |> Repo.all()
  end

  @doc """
  Gets an active deck by id, with `item_count` populated.

  Raises `Ecto.NoResultsError` if the deck does not exist.
  """
  def get_deck!(id) do
    Queries.active_decks_with_item_counts() |> Queries.by_id(id) |> Repo.one!()
  end

  @doc """
  Lists active decks of `kind` with their active items preloaded in order.
  """
  def list_decks_with_items(kind) do
    Queries.active_decks()
    |> Queries.of_kind(kind)
    |> Queries.in_curriculum_order()
    |> Queries.with_active_items()
    |> Repo.all()
  end

  @doc """
  Gets an active deck by slug with its active items preloaded in order.

  Raises `Ecto.NoResultsError` if the deck does not exist.
  """
  def get_deck_by_slug!(slug) do
    Queries.active_decks() |> Queries.by_slug(slug) |> Queries.with_active_items() |> Repo.one!()
  end

  @doc "Gets an active deck by slug, without its items. Returns `nil` if not found."
  def get_deck_by_slug(slug) when is_binary(slug) do
    Queries.active_decks() |> Queries.by_slug(slug) |> Repo.one()
  end

  ## Grammar

  @doc """
  Lists active grammar points in curriculum order, each with `learned_at`
  set for the scope's user (`nil` for anonymous visitors).
  """
  def list_grammar_points(scope \\ nil) do
    scope
    |> user_id()
    |> Queries.active_grammar_points()
    |> Queries.in_lesson_order()
    |> Repo.all()
  end

  @doc """
  Gets an active grammar point by slug, with `learned_at` for the scope's
  user, its deck, and its active example sentences preloaded in order.

  Raises `Ecto.NoResultsError` if the point does not exist.
  """
  def get_grammar_point_by_slug!(scope, slug) do
    scope
    |> user_id()
    |> Queries.active_grammar_points()
    |> Queries.by_slug(slug)
    |> Queries.with_deck_and_examples()
    |> Repo.one!()
  end

  defp user_id(%Scope{user: user}), do: user.id
  defp user_id(nil), do: nil

  @doc """
  Returns the set of grammar point ids the scope's user has learned.
  Anonymous visitors have learned nothing.
  """
  def learned_grammar_point_ids(nil), do: MapSet.new()

  def learned_grammar_point_ids(%Scope{user: user}) do
    user.id |> Queries.learned_grammar_point_ids() |> Repo.all() |> MapSet.new()
  end

  @doc """
  Marks `point` as learned, which unlocks its example sentences as cloze
  cards. Marking it twice keeps the original `learned_at`.
  """
  def mark_grammar_learned(%Scope{user: user}, %GrammarPoint{id: point_id}, now \\ nil) do
    Repo.insert(
      %GrammarProgress{
        user_id: user.id,
        grammar_point_id: point_id,
        learned_at: now || DateTime.utc_now(:second)
      },
      on_conflict: :nothing,
      conflict_target: [:user_id, :grammar_point_id]
    )
  end

  @doc """
  Undoes `mark_grammar_learned/3`. The point's sentences leave the study
  queue; cards already introduced keep their history and come back where
  they left off if the point is marked as learned again.
  """
  def unmark_grammar_learned(%Scope{user: user}, %GrammarPoint{id: point_id}) do
    {count, _} = Repo.delete_all(Queries.grammar_progress(user.id, point_id))
    {:ok, count}
  end
end
