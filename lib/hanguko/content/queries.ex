defmodule Hanguko.Content.Queries do
  @moduledoc """
  Queries over the curriculum, used by `Hanguko.Content`, its importer, and
  the study queue.

  Functions here build `Ecto.Query` structs and never touch the database; the
  caller decides what to run, and inside which transaction. Queries name
  their bindings (`:deck`, `:item`, `:grammar_point`) so the narrowing
  functions can be chained onto any query that has the binding they need.
  """
  import Ecto.Query, warn: false

  alias Hanguko.Content.{Deck, GrammarPoint, GrammarProgress, Item}

  ## Decks

  @doc "Decks that haven't been retired."
  def active_decks, do: from(d in Deck, as: :deck, where: not d.retired)

  @doc "Active decks, each with `item_count` set to its number of active items."
  def active_decks_with_item_counts do
    item_counts =
      from i in Item,
        where: not i.retired,
        group_by: i.deck_id,
        select: %{deck_id: i.deck_id, count: count(i.id)}

    from [deck: d] in active_decks(),
      left_join: c in subquery(item_counts),
      on: c.deck_id == d.id,
      select_merge: %{item_count: coalesce(c.count, 0)}
  end

  @doc """
  Narrows a deck query to one id, or to any id in a list or set. `nil` keeps
  every id.
  """
  def of_id(query, nil), do: query
  def of_id(query, %MapSet{} = ids), do: where(query, [deck: d], d.id in ^MapSet.to_list(ids))
  def of_id(query, ids) when is_list(ids), do: where(query, [deck: d], d.id in ^ids)
  def of_id(query, id), do: where(query, [deck: d], d.id == ^id)

  @doc """
  Narrows a deck query to one kind, or to any kind in a list. `nil` keeps
  every kind.
  """
  def of_kind(query, nil), do: query
  def of_kind(query, kinds) when is_list(kinds), do: where(query, [deck: d], d.kind in ^kinds)
  def of_kind(query, kind), do: where(query, [deck: d], d.kind == ^kind)

  @doc """
  Orders a query with a `:deck` binding the way the curriculum is taught: by
  kind, in the order of `Deck.kinds/0`, then level and position.
  """
  def in_curriculum_order(query) do
    kinds = Enum.map(Deck.kinds(), &Atom.to_string/1)

    order_by(query, [deck: d], [
      fragment("array_position(?::text[], ?::text)", ^kinds, d.kind),
      d.level,
      d.position,
      d.id
    ])
  end

  @doc "Narrows a query with a `:deck` binding to the deck with `id`."
  def deck_by_id(query, id), do: where(query, [deck: d], d.id == ^id)

  @doc "Narrows a query with a `:deck` binding to the deck with `slug`."
  def deck_by_slug(query, slug), do: where(query, [deck: d], d.slug == ^slug)

  @doc "Preloads each deck's active items, in position order."
  def with_active_items(query), do: preload(query, items: ^active_items())

  ## Items

  @doc "Items that haven't been retired, in position order."
  def active_items do
    from i in Item, as: :item, where: not i.retired, order_by: [i.position, i.id]
  end

  @doc """
  Narrows a query with an `:item` binding to what `user_id` may study: items
  that belong to no grammar point, and example sentences whose grammar point
  the user has marked as learned.
  """
  def unlocked_for(query, user_id) do
    query
    |> join(:left, [item: i], p in GrammarProgress,
      as: :unlocked_by,
      on: p.grammar_point_id == i.grammar_point_id and p.user_id == ^user_id
    )
    |> where([item: i, unlocked_by: p], is_nil(i.grammar_point_id) or not is_nil(p.id))
  end

  ## Grammar

  @doc """
  Grammar points that haven't been retired. Given a user id, each has
  `learned_at` set from that user's progress (`nil` when not learned).
  """
  def active_grammar_points(user_id \\ nil)

  def active_grammar_points(nil) do
    from g in GrammarPoint, as: :grammar_point, where: not g.retired
  end

  def active_grammar_points(user_id) do
    from [grammar_point: g] in active_grammar_points(nil),
      left_join: p in GrammarProgress,
      on: p.grammar_point_id == g.id and p.user_id == ^user_id,
      select_merge: %{learned_at: p.learned_at}
  end

  @doc "Narrows a query with a `:grammar_point` binding to the point with `slug`."
  def grammar_point_by_slug(query, slug),
    do: where(query, [grammar_point: g], g.slug == ^slug)

  @doc """
  Orders grammar points as lessons: by level, then their deck's position,
  then their own.
  """
  def in_lesson_order(query) do
    query
    |> join(:left, [grammar_point: g], d in assoc(g, :deck), as: :deck)
    |> order_by([grammar_point: g, deck: d], [g.level, d.position, g.position, g.id])
  end

  @doc "Preloads a grammar point's deck and its active example sentences, in order."
  def with_deck_and_examples(query), do: preload(query, [:deck, items: ^active_items()])

  @doc "The ids of the grammar points `user_id` has marked as learned."
  def learned_grammar_point_ids(user_id) do
    from p in GrammarProgress, where: p.user_id == ^user_id, select: p.grammar_point_id
  end

  @doc "`user_id`'s progress on one grammar point: at most one row."
  def grammar_progress(user_id, grammar_point_id) do
    from p in GrammarProgress,
      where: p.user_id == ^user_id and p.grammar_point_id == ^grammar_point_id
  end

  ## Importing

  @doc """
  Active decks whose slug isn't among `slugs`: those that have left the
  packs, which the importer retires.
  """
  def missing_decks(slugs), do: from(d in Deck, where: d.slug not in ^slugs and not d.retired)

  @doc "Active items whose source key isn't among `source_keys`."
  def missing_items(source_keys) do
    from i in Item, where: i.source_key not in ^source_keys and not i.retired
  end

  @doc "Active grammar points whose slug isn't among `slugs`."
  def missing_grammar_points(slugs) do
    from g in GrammarPoint, where: g.slug not in ^slugs and not g.retired
  end
end
