defmodule Hanguko.Content do
  @moduledoc """
  The global curriculum: decks and their items. Content is read-only at
  runtime; it is maintained as YAML packs in `priv/content` and loaded with
  `mix hanguko.content.import`.
  """
  import Ecto.Query, warn: false

  alias Hanguko.Accounts.Scope
  alias Hanguko.Repo
  alias Hanguko.Content.{Deck, GrammarPoint, GrammarProgress, Item}

  @doc """
  Lists active decks with `item_count` populated, in curriculum order: by
  kind (in the order of `Deck.kinds/0`), then level and position.

  ## Options

    * `:kind` - only return decks of this kind, or of any kind in this list
  """
  def list_decks(opts \\ []) do
    kinds = Enum.map(Deck.kinds(), &Atom.to_string/1)

    decks_with_counts_query()
    |> filter_kind(opts[:kind])
    |> order_by([d], [
      fragment("array_position(?::text[], ?::text)", ^kinds, d.kind),
      d.level,
      d.position,
      d.id
    ])
    |> Repo.all()
  end

  @doc """
  Gets an active deck by id, with `item_count` populated.

  Raises `Ecto.NoResultsError` if the deck does not exist.
  """
  def get_deck!(id) do
    decks_with_counts_query() |> where([d], d.id == ^id) |> Repo.one!()
  end

  defp decks_with_counts_query do
    item_counts =
      from i in Item,
        where: not i.retired,
        group_by: i.deck_id,
        select: %{deck_id: i.deck_id, count: count(i.id)}

    from d in Deck,
      where: not d.retired,
      left_join: c in subquery(item_counts),
      on: c.deck_id == d.id,
      select_merge: %{item_count: coalesce(c.count, 0)}
  end

  @doc """
  Lists active decks of `kind` with their active items preloaded in order.
  """
  def list_decks_with_items(kind) do
    Deck
    |> where([d], not d.retired)
    |> filter_kind(kind)
    |> order_by([d], [d.level, d.position, d.id])
    |> preload(items: ^active_items_query())
    |> Repo.all()
  end

  @doc """
  Gets an active deck by slug with its active items preloaded in order.

  Raises `Ecto.NoResultsError` if the deck does not exist.
  """
  def get_deck_by_slug!(slug) do
    Deck
    |> where([d], d.slug == ^slug and not d.retired)
    |> preload(items: ^active_items_query())
    |> Repo.one!()
  end

  @doc "Gets an active deck by slug, without its items. Returns `nil` if not found."
  def get_deck_by_slug(slug) when is_binary(slug) do
    Repo.one(from d in Deck, where: d.slug == ^slug and not d.retired)
  end

  defp active_items_query do
    from i in Item, where: not i.retired, order_by: [i.position, i.id]
  end

  defp filter_kind(query, nil), do: query
  defp filter_kind(query, kinds) when is_list(kinds), do: where(query, [d], d.kind in ^kinds)
  defp filter_kind(query, kind), do: where(query, [d], d.kind == ^kind)

  ## Grammar

  @doc """
  Lists active grammar points in curriculum order, each with `learned_at`
  set for the scope's user (`nil` for anonymous visitors).
  """
  def list_grammar_points(scope \\ nil) do
    grammar_points_query(scope)
    |> join(:left, [g], d in assoc(g, :deck), as: :deck)
    |> order_by([g, deck: d], [g.level, d.position, g.position, g.id])
    |> Repo.all()
  end

  @doc """
  Gets an active grammar point by slug, with `learned_at` for the scope's
  user, its deck, and its active example sentences preloaded in order.

  Raises `Ecto.NoResultsError` if the point does not exist.
  """
  def get_grammar_point_by_slug!(scope, slug) do
    grammar_points_query(scope)
    |> where([g], g.slug == ^slug)
    |> preload([:deck, items: ^active_items_query()])
    |> Repo.one!()
  end

  defp grammar_points_query(scope) do
    query = from g in GrammarPoint, where: not g.retired

    case scope do
      %Scope{user: user} ->
        from g in query,
          left_join: p in GrammarProgress,
          on: p.grammar_point_id == g.id and p.user_id == ^user.id,
          select_merge: %{learned_at: p.learned_at}

      nil ->
        query
    end
  end

  @doc """
  Returns the set of grammar point ids the scope's user has learned.
  Anonymous visitors have learned nothing.
  """
  def learned_grammar_point_ids(nil), do: MapSet.new()

  def learned_grammar_point_ids(%Scope{user: user}) do
    GrammarProgress
    |> where([p], p.user_id == ^user.id)
    |> select([p], p.grammar_point_id)
    |> Repo.all()
    |> MapSet.new()
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
  Undoes `mark_grammar_learned/3`. Cards already introduced keep their
  history; they simply stop being studied.
  """
  def unmark_grammar_learned(%Scope{user: user}, %GrammarPoint{id: point_id}) do
    {count, _} =
      Repo.delete_all(
        from p in GrammarProgress,
          where: p.user_id == ^user.id and p.grammar_point_id == ^point_id
      )

    {:ok, count}
  end
end
