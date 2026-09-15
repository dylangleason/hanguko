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
    * Example sentences are only studied while their grammar point is
      marked as learned, both when introduced and afterwards.
    * Then new cards, up to the daily new limit. The limit is shared by all
      enrolled decks, which take turns (one card from each, in curriculum
      order); within a deck, items come in position order. Recognition cards
      are introduced first; an item's recall card becomes available the day
      after its recognition card, and the two kinds are interleaved.
    * `new_limit_reached` / `review_limit_reached` are true when that daily
      limit is used up while more cards are waiting.
    * Siblings (the other template of the same item) are buried: an item is
      reviewed at most once per day in the review/new queues.
    * When nothing else is left, learning cards due within the next 20
      minutes are shown early.

  The queries it runs are built in `Hanguko.SRS.Queries`.
  """
  alias Hanguko.Repo
  alias Hanguko.Content.Item
  alias Hanguko.SRS.{Card, Day, Queries, Settings}

  @learn_ahead_seconds 20 * 60

  defstruct learning: [],
            review: [],
            new: [],
            learning_ahead: [],
            next_learning_due: nil,
            new_limit_reached: false,
            review_limit_reached: false,
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

        {review, review_limit_reached} =
          review_cards(user_id, deck_ids, settings, day_start, day_end, reviewed_today)

        busy_items =
          MapSet.union(
            MapSet.new(reviewed_today, fn {item_id, _card_id} -> item_id end),
            MapSet.new(learning ++ ahead ++ review, & &1.item.id)
          )

        {new, new_limit_reached} = new_entries(user_id, deck_ids, settings, day_start, busy_items)

        %{
          queue
          | learning: learning,
            learning_ahead: ahead,
            review: review,
            new: new,
            new_limit_reached: new_limit_reached,
            review_limit_reached: review_limit_reached,
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
    user_id |> Queries.studied_deck_ids() |> Queries.in_deck(deck_id) |> Repo.all()
  end

  # Un-marking a grammar point puts its sentences aside, history and all:
  # `studied_cards/2` leaves them out.
  defp due_cards(user_id, deck_ids, states, day_end) do
    user_id
    |> Queries.studied_cards(deck_ids)
    |> Queries.in_state(states)
    |> Queries.due_before(day_end)
    |> Queries.in_due_order()
    |> Repo.all()
  end

  defp learning_cards(user_id, deck_ids, now, day_end) do
    cards = due_cards(user_id, deck_ids, [:learning, :relearning], day_end)

    learn_ahead_until = DateTime.add(now, @learn_ahead_seconds)
    {due, not_due} = Enum.split_with(cards, &(DateTime.compare(&1.due, now) != :gt))

    {ahead, later} =
      Enum.split_with(not_due, &(DateTime.compare(&1.due, learn_ahead_until) != :gt))

    {Enum.map(due, &entry/1), Enum.map(ahead, &entry/1), Enum.map(later, &entry/1)}
  end

  # Returns {entries, limit_reached?}.
  defp review_cards(user_id, deck_ids, settings, day_start, day_end, reviewed_today) do
    budget = max(settings.daily_review_limit - reviews_done_since(user_id, day_start), 0)

    cards = due_cards(user_id, deck_ids, :review, day_end)

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

    {Enum.take(entries, budget), budget == 0 and entries != []}
  end

  defp reviews_done_since(user_id, day_start) do
    user_id
    |> Queries.review_logs()
    |> Queries.reviewed_since(day_start)
    |> Queries.of_review_cards()
    |> Repo.aggregate(:count)
  end

  defp items_reviewed_since(user_id, day_start) do
    user_id
    |> Queries.review_logs()
    |> Queries.reviewed_since(day_start)
    |> Queries.reviewed_item_cards()
    |> Repo.all()
  end

  defp entry(%Card{} = card), do: %{card: card, item: card.item, template: card.template}

  ## New cards

  defp new_entries(user_id, deck_ids, settings, day_start, busy_items) do
    introduced_today =
      user_id
      |> Queries.cards()
      |> Queries.introduced_since(day_start)
      |> Repo.aggregate(:count)

    budget = max(settings.daily_new_limit - introduced_today, 0)

    # With no budget left, still look for one card to know if any are waiting.
    candidates = find_new_entries(user_id, deck_ids, day_start, busy_items, max(budget, 1))
    {Enum.take(candidates, budget), budget == 0 and candidates != []}
  end

  # Up to `count` new entries, taking one from each deck in turn. Example
  # sentences wait until their grammar point has been marked as learned.
  defp find_new_entries(user_id, deck_ids, day_start, busy_items, count) do
    items = user_id |> Queries.unlocked_items(deck_ids) |> Repo.all()

    # {item_id, template} => introduced_at, for the user's existing cards
    existing = user_id |> Queries.card_introductions(deck_ids) |> Repo.all() |> Map.new()

    # Items are sorted by deck, so chunking groups each deck's items.
    items
    |> Enum.chunk_by(& &1.deck_id)
    |> Enum.map(&deck_new_entries(&1, existing, busy_items, day_start, count))
    |> round_robin()
    |> Enum.take(count)
  end

  # One deck's new entries in position order, alternating between items'
  # first cards (recognition, or cloze for example sentences) and, from the
  # day after, their recall cards.
  defp deck_new_entries(items, existing, busy_items, day_start, count) do
    first =
      items
      |> Stream.flat_map(fn item ->
        case Card.templates_for(item) do
          [template | _] -> [{item, template}]
          [] -> []
        end
      end)
      |> Stream.reject(fn {item, template} -> Map.has_key?(existing, {item.id, template}) end)
      |> Stream.map(fn {item, template} -> %{card: nil, item: item, template: template} end)

    recall =
      items
      |> Stream.filter(fn item ->
        :recall in Card.templates_for(item) and not Map.has_key?(existing, {item.id, :recall}) and
          not MapSet.member?(busy_items, item.id) and
          introduced_before?(existing[{item.id, :recognition}], day_start)
      end)
      |> Stream.map(&%{card: nil, item: &1, template: :recall})

    interleave(Enum.take(first, count), Enum.take(recall, count))
  end

  # [[a1, a2, a3], [b1]] -> [a1, b1, a2, a3]
  defp round_robin(lists) do
    case Enum.reject(lists, &(&1 == [])) do
      [] -> []
      lists -> Enum.map(lists, &hd/1) ++ round_robin(Enum.map(lists, &tl/1))
    end
  end

  defp introduced_before?(nil, _day_start), do: false

  defp introduced_before?(introduced_at, day_start),
    do: DateTime.before?(introduced_at, day_start)

  defp interleave([a | as], [b | bs]), do: [a, b | interleave(as, bs)]
  defp interleave(as, []), do: as
  defp interleave([], bs), do: bs
end
