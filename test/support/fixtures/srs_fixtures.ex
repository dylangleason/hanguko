defmodule Hanguko.SRSFixtures do
  @moduledoc """
  Test helpers for creating cards in a given scheduling state.
  """

  alias Hanguko.Repo
  alias Hanguko.SRS.{Card, ReviewLog}

  @doc """
  Inserts a card for `user` and `item`. Defaults to a review card that is
  due at `attrs[:due]` (or now).
  """
  def card_fixture(user, item, attrs \\ %{}) do
    now = DateTime.utc_now(:second)

    %Card{
      user_id: user.id,
      item_id: item.id,
      template: :recognition,
      state: :review,
      stability: 5.0,
      difficulty: 5.0,
      due: now,
      last_review_at: DateTime.add(now, -5, :day),
      introduced_at: DateTime.add(now, -10, :day),
      reps: 3
    }
    |> struct(Map.new(attrs))
    |> Repo.insert!()
  end

  @doc """
  Inserts a review of `card` by `user` at `reviewed_at`. Defaults to a Good
  rating of a card that was already in review.
  """
  def review_log_fixture(user, card, reviewed_at, attrs \\ %{}) do
    %ReviewLog{
      user_id: user.id,
      card_id: card.id,
      rating: 3,
      reviewed_at: reviewed_at,
      duration_ms: 5_000,
      scheduled_seconds: 86_400,
      state_before: :review,
      state_after: :review
    }
    |> struct(Map.new(attrs))
    |> Repo.insert!()
  end
end
