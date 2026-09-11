defmodule Hanguko.SRS.Scheduler do
  @moduledoc """
  Spaced-repetition scheduling with FSRS (via `fsrs_ex`, a port of the
  reference py-fsrs implementation of FSRS-6).

  This module is the only place that talks to the FSRS library: it converts
  between `Hanguko.SRS.Card` and `Fsrs.Card` and is otherwise pure.

  Ratings are integers: 1 = Again, 2 = Hard, 3 = Good, 4 = Easy.
  """
  alias Hanguko.SRS.Card

  @ratings %{1 => :again, 2 => :hard, 3 => :good, 4 => :easy}

  @doc "The valid ratings, lowest first."
  def ratings, do: [1, 2, 3, 4]

  @doc """
  Schedules a review of `card` (`nil` for a card that has never been
  studied) rated `rating` at `now`.

  Returns the card's new scheduling fields: `:state`, `:step`, `:stability`,
  `:difficulty`, `:due` and `:last_review_at`.

  ## Options

    * `:desired_retention` - target probability of recall (default 0.9)
    * `:fuzz` - randomize review intervals slightly (default from config)
  """
  def review(card, rating, %DateTime{} = now, opts \\ []) when is_map_key(@ratings, rating) do
    now = DateTime.truncate(now, :second)

    {fsrs_card, _log} =
      Fsrs.Scheduler.review_card(scheduler(opts), to_fsrs(card, now), @ratings[rating], now)

    %{
      state: fsrs_card.state,
      step: fsrs_card.step,
      stability: fsrs_card.stability,
      difficulty: fsrs_card.difficulty,
      due: DateTime.truncate(fsrs_card.due, :second),
      last_review_at: now
    }
  end

  @doc """
  How many seconds until `card` would be due again for each rating, as a map
  of rating to seconds. Never fuzzed, so the numbers are stable.
  """
  def preview(card, %DateTime{} = now, opts \\ []) do
    now = DateTime.truncate(now, :second)
    opts = Keyword.put(opts, :fuzz, false)
    Map.new(ratings(), &{&1, DateTime.diff(review(card, &1, now, opts).due, now)})
  end

  defp scheduler(opts) do
    Fsrs.Scheduler.new(
      desired_retention: Keyword.get(opts, :desired_retention, 0.9),
      enable_fuzzing: Keyword.get_lazy(opts, :fuzz, &fuzz_default/0)
    )
  end

  defp fuzz_default, do: Application.get_env(:hanguko, Hanguko.SRS, [])[:fuzz] || false

  defp to_fsrs(nil, now), do: Fsrs.Card.new(card_id: 0, due: now)

  defp to_fsrs(%Card{} = card, _now) do
    %Fsrs.Card{
      card_id: card.id,
      state: card.state,
      step: card.step,
      stability: card.stability,
      difficulty: card.difficulty,
      due: card.due,
      last_review: card.last_review_at
    }
  end
end
