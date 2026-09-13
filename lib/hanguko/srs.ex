defmodule Hanguko.SRS do
  @moduledoc """
  Per-user study state: enrolled decks, study settings, flashcards and
  their review history.

  Functions that depend on the time take `now` explicitly so that behavior
  is deterministic and testable.
  """
  import Ecto.Query, warn: false

  alias Hanguko.Repo
  alias Hanguko.Accounts.Scope
  alias Hanguko.Content
  alias Hanguko.Content.Deck
  alias Hanguko.SRS.{Card, DeckEnrollment, Queue, ReviewLog, Scheduler, Settings}

  ## Enrollment

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

  @doc """
  Removes the scope's user from `deck`. Its cards stop being studied, but
  their history is kept and resumes if the user enrolls again.
  """
  def unenroll_deck(%Scope{user: user}, %Deck{id: deck_id}) do
    {count, _} =
      Repo.delete_all(
        from e in DeckEnrollment, where: e.user_id == ^user.id and e.deck_id == ^deck_id
      )

    {:ok, count}
  end

  @doc "Lists the decks the scope's user is enrolled in, in curriculum order."
  def list_enrolled_decks(%Scope{} = scope) do
    enrolled = enrolled_deck_ids(scope)
    Enum.filter(Content.list_decks(), &MapSet.member?(enrolled, &1.id))
  end

  ## Settings

  @doc """
  Returns the scope's study settings, or unsaved defaults. Anonymous
  visitors (a `nil` scope) get the defaults too.
  """
  def get_settings(nil), do: %Settings{}

  def get_settings(%Scope{user: user}) do
    Repo.get_by(Settings, user_id: user.id) || %Settings{user_id: user.id}
  end

  @doc "Returns a changeset for editing study settings."
  def change_settings(%Settings{} = settings, attrs \\ %{}) do
    Settings.changeset(settings, attrs)
  end

  @doc "Saves the scope's study settings."
  def update_settings(%Scope{} = scope, attrs) do
    scope |> get_settings() |> Settings.changeset(attrs) |> Repo.insert_or_update()
  end

  @doc """
  Remembers the time zone reported by the user's browser, unless one is
  already set. Returns the (possibly updated) settings.
  """
  def put_detected_timezone(%Scope{} = scope, timezone) do
    settings = get_settings(scope)

    with nil <- settings.timezone,
         true <- Settings.valid_timezone?(timezone),
         {:ok, settings} <- update_settings(scope, %{timezone: timezone}) do
      settings
    else
      _ -> settings
    end
  end

  ## Studying

  @doc """
  Builds the scope's study queue at `now`. See `Hanguko.SRS.Queue`.

  ## Options

    * `:deck` - only study this (enrolled) deck
    * `:settings` - the user's settings, if already loaded
  """
  def study_queue(%Scope{user: user} = scope, %DateTime{} = now, opts \\ []) do
    settings = opts[:settings] || get_settings(scope)
    deck_id = if deck = opts[:deck], do: deck.id
    Queue.build(user.id, settings, now, deck_id: deck_id)
  end

  @doc """
  The intervals each rating would give `entry`'s card, as a map of rating
  to seconds.
  """
  def preview_intervals(%Settings{} = settings, %{card: card}, %DateTime{} = now) do
    Scheduler.preview(card, now, desired_retention: settings.desired_retention)
  end

  @doc """
  Records a review of a queue entry. New cards are created on their first
  review.

  Returns `{:ok, review_log}`, or `{:error, :stale}` if a new card was
  created elsewhere (e.g. studied in another tab) since the entry was loaded.

  ## Options

    * `:duration_ms` - how long the user looked at the card
    * `:settings` - the user's settings, if already loaded
  """
  def review_card(%Scope{user: user} = scope, entry, rating, %DateTime{} = now, opts \\ []) do
    settings = opts[:settings] || get_settings(scope)
    now = DateTime.truncate(now, :second)

    Repo.transact(fn ->
      with {:ok, before} <- current_card(user, entry),
           schedule =
             Scheduler.review(before, rating, now, desired_retention: settings.desired_retention),
           {:ok, after_review} <- save_card(user, entry, before, schedule, rating, now) do
        %ReviewLog{
          user_id: user.id,
          card_id: after_review.id,
          rating: rating,
          reviewed_at: now,
          duration_ms: opts[:duration_ms],
          elapsed_days: before && DateTime.diff(now, before.last_review_at, :day),
          scheduled_seconds: DateTime.diff(after_review.due, now),
          state_before: before && before.state,
          step_before: before && before.step,
          stability_before: before && before.stability,
          difficulty_before: before && before.difficulty,
          due_before: before && before.due,
          last_review_before: before && before.last_review_at,
          state_after: after_review.state,
          stability_after: after_review.stability,
          difficulty_after: after_review.difficulty
        }
        |> Repo.insert()
      end
    end)
  end

  # Re-reads the card (locked) inside the transaction, so the review is
  # scheduled from its latest state even if it was reviewed in another tab.
  defp current_card(_user, %{card: nil}), do: {:ok, nil}

  defp current_card(user, %{card: %Card{id: id}}) do
    case Repo.one(
           from c in Card, where: c.id == ^id and c.user_id == ^user.id, lock: "FOR UPDATE"
         ) do
      %Card{} = card -> {:ok, card}
      nil -> {:error, :stale}
    end
  end

  defp save_card(user, entry, nil, schedule, _rating, now) do
    %Card{
      user_id: user.id,
      item_id: entry.item.id,
      template: entry.template,
      introduced_at: now,
      reps: 1
    }
    |> Ecto.Changeset.change(schedule)
    |> Ecto.Changeset.unique_constraint([:user_id, :item_id, :template])
    |> Repo.insert()
    |> stale_on_conflict()
  end

  defp save_card(_user, _entry, %Card{} = card, schedule, rating, _now) do
    lapsed? = card.state == :review and rating == 1

    card
    |> Ecto.Changeset.change(schedule)
    |> Ecto.Changeset.put_change(:reps, card.reps + 1)
    |> Ecto.Changeset.put_change(:lapses, card.lapses + if(lapsed?, do: 1, else: 0))
    |> Repo.update()
  end

  defp stale_on_conflict({:error, %Ecto.Changeset{}}), do: {:error, :stale}
  defp stale_on_conflict(result), do: result

  @doc """
  Undoes a review, restoring the card to its state before it (or deleting
  it, if the review was its first). Only a card's latest review can be
  undone.

  Returns `{:ok, entry}` with the queue entry to show again.
  """
  def undo_review(%Scope{user: user}, %ReviewLog{id: log_id}) do
    Repo.transact(fn ->
      log =
        Repo.one(
          from l in ReviewLog,
            where: l.id == ^log_id and l.user_id == ^user.id,
            preload: [card: :item]
        )

      cond do
        is_nil(log) ->
          {:error, :not_found}

        Repo.exists?(from l in ReviewLog, where: l.card_id == ^log.card_id and l.id > ^log.id) ->
          {:error, :not_latest}

        ReviewLog.first_review?(log) ->
          Repo.delete!(log.card)
          {:ok, %{card: nil, item: log.card.item, template: log.card.template}}

        true ->
          lapsed? = log.state_before == :review and log.rating == 1

          card =
            log.card
            |> Ecto.Changeset.change(
              state: log.state_before,
              step: log.step_before,
              stability: log.stability_before,
              difficulty: log.difficulty_before,
              due: log.due_before,
              last_review_at: log.last_review_before,
              reps: log.card.reps - 1,
              lapses: log.card.lapses - if(lapsed?, do: 1, else: 0)
            )
            |> Repo.update!()

          Repo.delete!(log)
          {:ok, %{card: card, item: log.card.item, template: card.template}}
      end
    end)
  end

  ## Dashboard

  @doc """
  Summarizes what the scope's user has to study today.

  Returns a map with:

    * `:decks` - enrolled decks with the number of cards `:due` and `:new`
      in today's queue
    * `:due`, `:new` - totals
    * `:reviewed_today` - reviews done so far today
    * `:next_learning_due` - when the next learning card comes back, if any
      are waiting later today
    * `:new_limit_reached`, `:review_limit_reached` - whether that daily
      limit is used up while more cards are waiting
    * `:settings` - the user's study settings
  """
  def summary(%Scope{user: user} = scope, %DateTime{} = now) do
    settings = get_settings(scope)
    queue = study_queue(scope, now, settings: settings)

    by_deck =
      queue
      |> Queue.entries()
      |> Enum.group_by(& &1.item.deck_id, &if(&1.card, do: :due, else: :new))
      |> Map.new(fn {deck_id, kinds} -> {deck_id, Enum.frequencies(kinds)} end)

    decks =
      for deck <- list_enrolled_decks(scope) do
        counts = Map.get(by_deck, deck.id, %{})
        %{deck: deck, due: Map.get(counts, :due, 0), new: Map.get(counts, :new, 0)}
      end

    reviewed_today =
      Repo.aggregate(
        from(l in ReviewLog, where: l.user_id == ^user.id and l.reviewed_at >= ^queue.day_start),
        :count
      )

    %{
      decks: decks,
      due: Enum.sum_by(decks, & &1.due),
      new: Enum.sum_by(decks, & &1.new),
      reviewed_today: reviewed_today,
      next_learning_due: queue.next_learning_due,
      new_limit_reached: queue.new_limit_reached,
      review_limit_reached: queue.review_limit_reached,
      settings: settings
    }
  end
end
