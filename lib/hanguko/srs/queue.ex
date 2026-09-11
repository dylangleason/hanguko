defmodule Hanguko.SRS.Queue do
  @moduledoc """
  Builds a user's study queue for the current study day.

  An entry is a map `%{card: card_or_nil, item: item, template: template}`;
  `card` is `nil` for a card that has not been studied yet.

  Rules:

    * Only cards of active items in the user's enrolled decks are studied.
    * Learning cards (in their minute-long learning steps) come first when due.
    * Review cards due before the end of the study day come next, oldest
      first, up to the daily review limit.
    * Then new cards, up to the daily new limit, in curriculum order (deck,
      then item position). Recognition cards are introduced first; an item's
      recall card becomes available the day after its recognition card, and
      the two kinds are interleaved.
    * Siblings (the other template of the same item) are buried: an item is
      reviewed at most once per day in the review/new queues.
    * When nothing else is left, learning cards due within the next 20
      minutes are shown early.
  """
  import Ecto.Query, warn: false

  alias Hanguko.Repo
  alias Hanguko.Content.{Deck, Item}
  alias Hanguko.SRS.{Card, Day, DeckEnrollment, ReviewLog, Settings}

  @learn_ahead_seconds 20 * 60

  defstruct learning: [],
            review: [],
            new: [],
            learning_ahead: [],
            next_learning_due: nil,
            day_start: nil,
            day_end: nil

  @type entry :: %{card: Card.t() | nil, item: Item.t(), template: atom()}

  @doc """
  Builds the queue for `user_id` at `now`.

  ## Options

    * `:deck_id` - only study this deck (it must be enrolled)
  """
  def build(user_id, %Settings{} = settings, %DateTime{} = now, opts \\ []) do
    {day_start, day_end} =
      Day.bounds(now, Settings.timezone(settings), settings.day_rollover_hour)

    queue = %__MODULE__{day_start: day_start, day_end: day_end}

    case deck_ids(user_id, opts[:deck_id]) do
      [] ->
        queue

      deck_ids ->
        {learning, ahead, later} = learning_cards(user_id, deck_ids, now, day_end)
        reviewed_today = items_reviewed_since(user_id, day_start)
        review = review_cards(user_id, deck_ids, settings, day_start, day_end, reviewed_today)

        busy_items =
          MapSet.union(
            MapSet.new(reviewed_today, fn {item_id, _card_id} -> item_id end),
            MapSet.new(learning ++ ahead ++ review, & &1.item.id)
          )

        new = new_entries(user_id, deck_ids, settings, day_start, busy_items)

        %{
          queue
          | learning: learning,
            learning_ahead: ahead,
            review: review,
            new: new,
            next_learning_due:
              later |> Enum.map(& &1.card.due) |> Enum.min(DateTime, fn -> nil end)
        }
    end
  end

  @doc "The next entry to study, or `nil` when there is nothing to study now."
  def next(%__MODULE__{learning: [entry | _]}), do: entry
  def next(%__MODULE__{review: [entry | _]}), do: entry
  def next(%__MODULE__{new: [entry | _]}), do: entry
  def next(%__MODULE__{learning_ahead: [entry | _]}), do: entry
  def next(%__MODULE__{}), do: nil

  @doc "Remaining counts by kind, as shown during a study session."
  def counts(%__MODULE__{} = queue) do
    %{
      new: length(queue.new),
      learning: length(queue.learning) + length(queue.learning_ahead),
      review: length(queue.review)
    }
  end

  @doc "All entries in the queue, in study order."
  def entries(%__MODULE__{} = queue),
    do: queue.learning ++ queue.review ++ queue.new ++ queue.learning_ahead

  ## Cards already being studied

  defp deck_ids(user_id, deck_id) do
    DeckEnrollment
    |> join(:inner, [e], d in Deck, on: d.id == e.deck_id)
    |> where([e, d], e.user_id == ^user_id and not d.retired)
    |> then(fn query -> if deck_id, do: where(query, [e], e.deck_id == ^deck_id), else: query end)
    |> select([e], e.deck_id)
    |> Repo.all()
  end

  defp cards_query(user_id, deck_ids) do
    from c in Card,
      join: i in assoc(c, :item),
      where: c.user_id == ^user_id and not c.suspended,
      where: i.deck_id in ^deck_ids and not i.retired,
      order_by: [c.due, c.id],
      preload: [item: i]
  end

  defp learning_cards(user_id, deck_ids, now, day_end) do
    cards =
      cards_query(user_id, deck_ids)
      |> where([c], c.state in [:learning, :relearning] and c.due < ^day_end)
      |> Repo.all()

    learn_ahead_until = DateTime.add(now, @learn_ahead_seconds)
    {due, not_due} = Enum.split_with(cards, &(DateTime.compare(&1.due, now) != :gt))

    {ahead, later} =
      Enum.split_with(not_due, &(DateTime.compare(&1.due, learn_ahead_until) != :gt))

    {Enum.map(due, &entry/1), Enum.map(ahead, &entry/1), Enum.map(later, &entry/1)}
  end

  defp review_cards(user_id, deck_ids, settings, day_start, day_end, reviewed_today) do
    budget = max(settings.daily_review_limit - reviews_done_since(user_id, day_start), 0)

    if budget == 0 do
      []
    else
      cards =
        cards_query(user_id, deck_ids)
        |> where([c], c.state == :review and c.due < ^day_end)
        |> Repo.all()

      # Bury siblings: skip a card if another card of its item was already
      # reviewed today or comes earlier in the queue.
      {entries, _seen} =
        Enum.flat_map_reduce(cards, MapSet.new(), fn card, seen ->
          sibling_reviewed? =
            Enum.any?(reviewed_today, fn {item_id, card_id} ->
              item_id == card.item_id and card_id != card.id
            end)

          if sibling_reviewed? or MapSet.member?(seen, card.item_id) do
            {[], seen}
          else
            {[entry(card)], MapSet.put(seen, card.item_id)}
          end
        end)

      Enum.take(entries, budget)
    end
  end

  defp reviews_done_since(user_id, day_start) do
    Repo.aggregate(
      from(l in ReviewLog,
        where: l.user_id == ^user_id and l.reviewed_at >= ^day_start and l.state_before == :review
      ),
      :count
    )
  end

  defp items_reviewed_since(user_id, day_start) do
    Repo.all(
      from l in ReviewLog,
        join: c in assoc(l, :card),
        where: l.user_id == ^user_id and l.reviewed_at >= ^day_start,
        distinct: true,
        select: {c.item_id, c.id}
    )
  end

  defp entry(%Card{} = card), do: %{card: card, item: card.item, template: card.template}

  ## New cards

  defp new_entries(user_id, deck_ids, settings, day_start, busy_items) do
    introduced_today =
      Repo.aggregate(
        from(c in Card, where: c.user_id == ^user_id and c.introduced_at >= ^day_start),
        :count
      )

    case max(settings.daily_new_limit - introduced_today, 0) do
      0 -> []
      budget -> find_new_entries(user_id, deck_ids, day_start, busy_items, budget)
    end
  end

  defp find_new_entries(user_id, deck_ids, day_start, busy_items, budget) do
    kinds = Enum.map(Deck.kinds(), &Atom.to_string/1)

    items =
      Repo.all(
        from i in Item,
          join: d in assoc(i, :deck),
          where: i.deck_id in ^deck_ids and not i.retired,
          order_by: [
            fragment("array_position(?::text[], ?::text)", ^kinds, d.kind),
            d.level,
            d.position,
            d.id,
            i.position,
            i.id
          ]
      )

    # {item_id, template} => introduced_at, for the user's existing cards
    existing =
      Repo.all(
        from c in Card,
          join: i in assoc(c, :item),
          where: c.user_id == ^user_id and i.deck_id in ^deck_ids,
          select: {{c.item_id, c.template}, c.introduced_at}
      )
      |> Map.new()

    recognition =
      Stream.filter(
        items,
        &(:recognition in Card.templates_for(&1) and
            not Map.has_key?(existing, {&1.id, :recognition}))
      )
      |> Stream.map(&%{card: nil, item: &1, template: :recognition})

    recall =
      items
      |> Stream.filter(fn item ->
        :recall in Card.templates_for(item) and not Map.has_key?(existing, {item.id, :recall}) and
          not MapSet.member?(busy_items, item.id) and
          introduced_before?(existing[{item.id, :recognition}], day_start)
      end)
      |> Stream.map(&%{card: nil, item: &1, template: :recall})

    interleave(Enum.take(recognition, budget), Enum.take(recall, budget))
    |> Enum.take(budget)
  end

  defp introduced_before?(nil, _day_start), do: false

  defp introduced_before?(introduced_at, day_start),
    do: DateTime.before?(introduced_at, day_start)

  defp interleave([a | as], [b | bs]), do: [a, b | interleave(as, bs)]
  defp interleave(as, []), do: as
  defp interleave([], bs), do: bs
end
