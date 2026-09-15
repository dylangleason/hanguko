defmodule Hanguko.SRS.Queries do
  @moduledoc """
  Queries over per-user study state: enrolments, cards and review logs. Used
  by `Hanguko.SRS`, the study queue (`Hanguko.SRS.Queue`) and
  `Hanguko.Progress`.

  Like `Hanguko.Content.Queries`, functions here only build queries. Queries
  name their bindings (`:enrollment`, `:card`, `:item`, `:log`) so the
  narrowing functions chain onto any query that has the binding they need.
  """
  import Ecto.Query, warn: false

  alias Hanguko.Content.{Deck, Item}
  alias Hanguko.Content.Queries, as: ContentQueries
  alias Hanguko.SRS.{Card, DeckEnrollment, ReviewLog}

  ## Enrolments

  @doc "The ids of every deck `user_id` is enrolled in."
  def enrolled_deck_ids(user_id) do
    from e in DeckEnrollment,
      as: :enrollment,
      where: e.user_id == ^user_id,
      select: e.deck_id
  end

  @doc """
  The ids of the decks `user_id` studies: enrolled decks that haven't been
  retired.
  """
  def studied_deck_ids(user_id) do
    from [enrollment: e] in enrolled_deck_ids(user_id),
      join: d in Deck,
      on: d.id == e.deck_id,
      where: not d.retired
  end

  @doc "`user_id`'s enrolment in one deck: at most one row."
  def enrollment(user_id, deck_id) do
    from e in DeckEnrollment, where: e.user_id == ^user_id and e.deck_id == ^deck_id
  end

  @doc "Narrows an enrolment query to one deck. `nil` keeps every deck."
  def in_deck(query, nil), do: query
  def in_deck(query, deck_id), do: where(query, [enrollment: e], e.deck_id == ^deck_id)

  ## Cards

  @doc "All of `user_id`'s cards."
  def cards(user_id), do: from(c in Card, as: :card, where: c.user_id == ^user_id)

  @doc """
  The cards study sessions draw from: `user_id`'s unsuspended cards of active
  items in `deck_ids`, leaving out example sentences whose grammar point
  isn't marked as learned. Unordered, with the item joined as `:item`.
  """
  def studied_cards(user_id, deck_ids) do
    user_id
    |> active_cards()
    |> where([card: c, item: i], not c.suspended and i.deck_id in ^deck_ids)
    |> ContentQueries.unlocked_for(user_id)
  end

  @doc """
  `user_id`'s cards of items that haven't been retired, whether or not their
  deck is still enrolled, with the item joined as `:item`.
  """
  def active_cards(user_id) do
    from [card: c] in cards(user_id),
      join: i in assoc(c, :item),
      as: :item,
      where: not i.retired
  end

  @doc "Narrows a card query to cards in `state`, or any state in a list."
  def in_state(query, states) when is_list(states),
    do: where(query, [card: c], c.state in ^states)

  def in_state(query, state), do: where(query, [card: c], c.state == ^state)

  @doc "Narrows a card query to cards due before `instant`."
  def due_before(query, instant), do: where(query, [card: c], c.due < ^instant)

  @doc "Narrows a card query to cards first studied at or after `instant`."
  def introduced_since(query, instant),
    do: where(query, [card: c], c.introduced_at >= ^instant)

  @doc """
  Orders a query from `studied_cards/2` by due date, oldest first, and
  preloads each card's item from the join.
  """
  def in_due_order(query) do
    query
    |> order_by([card: c], [c.due, c.id])
    |> preload([item: i], item: i)
  end

  @doc """
  One of `user_id`'s cards, locked `FOR UPDATE`, so a review in one tab waits
  for a review of the same card in another.
  """
  def card_for_update(user_id, card_id) do
    from [card: c] in cards(user_id), where: c.id == ^card_id, lock: "FOR UPDATE"
  end

  @doc """
  When each of `user_id`'s cards in `deck_ids` was introduced, as
  `{{item_id, template}, introduced_at}` pairs. The queue uses this to know
  which cards are still new, and when an item's recall card may follow.
  """
  def card_introductions(user_id, deck_ids) do
    from [card: c] in cards(user_id),
      join: i in assoc(c, :item),
      where: i.deck_id in ^deck_ids,
      select: {{c.item_id, c.template}, c.introduced_at}
  end

  @doc """
  Active items in `deck_ids` that `user_id` may study, in curriculum order:
  deck by deck (see `Hanguko.Content.Queries.in_curriculum_order/1`), then by
  position within each deck.
  """
  def unlocked_items(user_id, deck_ids) do
    from(i in Item,
      as: :item,
      join: d in assoc(i, :deck),
      as: :deck,
      where: i.deck_id in ^deck_ids and not i.retired
    )
    |> ContentQueries.unlocked_for(user_id)
    |> ContentQueries.in_curriculum_order()
    |> order_by([item: i], [i.position, i.id])
  end

  ## Browsing

  @doc """
  The cards the card browser lists: every card of `user_id`'s whose item is
  still active, in any deck, enrolled or not — a card the learner stopped
  studying is exactly what they come to the browser to find.

  Narrow it with the functions below, then order and preload it.
  """
  def browsable_cards(user_id) do
    from [item: i] in active_cards(user_id), join: d in assoc(i, :deck), as: :deck
  end

  @doc "Preloads each card's item, and the item's deck, from the joins."
  def with_item_and_deck(query), do: preload(query, [item: i, deck: d], item: {i, deck: d})

  @doc """
  Narrows a card query to items whose Korean, meaning or romanization
  contains `term`. A blank term keeps every card.
  """
  def matching(query, term) when term in [nil, ""], do: query

  def matching(query, term) do
    pattern = "%" <> escape_like(term) <> "%"

    where(
      query,
      [item: i],
      ilike(i.korean, ^pattern) or ilike(i.meaning, ^pattern) or ilike(i.romanization, ^pattern)
    )
  end

  # `%` and `_` are wildcards in LIKE, so without this a search for "_" would
  # match every card rather than the cards containing an underscore.
  defp escape_like(term) do
    term
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  @doc "Narrows a card query to the cards of one deck. `nil` keeps every deck."
  def of_deck(query, nil), do: query
  def of_deck(query, deck_id), do: where(query, [item: i], i.deck_id == ^deck_id)

  @doc "Narrows a card query to one template. `nil` keeps every template."
  def of_template(query, nil), do: query
  def of_template(query, template), do: where(query, [card: c], c.template == ^template)

  @doc """
  Narrows a card query by the status the browser filters on: `:active` (in
  the queue as usual), `:suspended`, `:leech` (see `Hanguko.SRS.Card.leech?/1`)
  or `:all`.
  """
  def with_status(query, :all), do: query
  def with_status(query, :active), do: where(query, [card: c], not c.suspended)
  def with_status(query, :suspended), do: where(query, [card: c], c.suspended)
  def with_status(query, :leech), do: where(query, [card: c], c.lapses >= ^Card.leech_lapses())

  @doc "Orders a card query by when each card comes up next, soonest first."
  def in_browse_order(query), do: order_by(query, [card: c], [c.due, c.id])

  @doc "Limits a query to at most `count` rows."
  def limit_to(query, count), do: limit(query, ^count)

  @doc "One of `user_id`'s cards, with its item and that item's deck preloaded."
  def card_with_content(user_id, card_id) do
    user_id |> browsable_cards() |> where([card: c], c.id == ^card_id) |> with_item_and_deck()
  end

  @doc "The ids of the decks `user_id` has cards in, for the browser's deck filter."
  def card_deck_ids(user_id) do
    from [item: i] in active_cards(user_id), distinct: true, select: i.deck_id
  end

  ## Review logs

  @doc "All of `user_id`'s reviews."
  def review_logs(user_id), do: from(l in ReviewLog, as: :log, where: l.user_id == ^user_id)

  @doc "One of `user_id`'s reviews, with its card and the card's item preloaded."
  def review_log(user_id, log_id) do
    from [log: l] in review_logs(user_id), where: l.id == ^log_id, preload: [card: :item]
  end

  @doc "Reviews of the same card made after `log`."
  def later_reviews(%ReviewLog{card_id: card_id, id: id}) do
    from l in ReviewLog, where: l.card_id == ^card_id and l.id > ^id
  end

  @doc "Narrows a review log query to reviews made at or after `instant`."
  def reviewed_since(query, instant), do: where(query, [log: l], l.reviewed_at >= ^instant)

  @doc """
  Narrows a review log query to reviews of cards that were already in review,
  leaving out learning and relearning steps.
  """
  def of_review_cards(query), do: where(query, [log: l], l.state_before == :review)

  @doc """
  The distinct `{item_id, card_id}` pairs a review log query covers, which the
  queue uses to bury the siblings of cards reviewed today.
  """
  def reviewed_item_cards(query) do
    from [log: l] in query,
      join: c in assoc(l, :card),
      distinct: true,
      select: {c.item_id, c.id}
  end
end
