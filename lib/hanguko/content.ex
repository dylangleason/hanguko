defmodule Hanguko.Content do
  @moduledoc """
  The global curriculum: decks and their items. Content is read-only at
  runtime; it is maintained as YAML packs in `priv/content` and loaded with
  `mix hanguko.content.import`.
  """
  import Ecto.Query, warn: false

  alias Hanguko.Repo
  alias Hanguko.Content.{Deck, Item}

  @doc """
  Lists active decks with `item_count` populated, in curriculum order: by
  kind (in the order of `Deck.kinds/0`), then level and position.

  ## Options

    * `:kind` - only return decks of this kind
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

  defp active_items_query do
    from i in Item, where: not i.retired, order_by: [i.position, i.id]
  end

  defp filter_kind(query, nil), do: query
  defp filter_kind(query, kind), do: where(query, [d], d.kind == ^kind)
end
