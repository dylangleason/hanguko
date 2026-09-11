defmodule Hanguko.SRS.SchedulerTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Hanguko.SRS.{Card, Scheduler}

  @now ~U[2026-09-11 12:00:00Z]

  defp apply_review(card, rating, now) do
    schedule = Scheduler.review(card, rating, now, fuzz: false)
    struct(card || %Card{id: 1}, schedule)
  end

  describe "new cards" do
    test "go through the learning steps" do
      assert %{state: :learning, step: 1, due: due} = Scheduler.review(nil, 3, @now, fuzz: false)
      assert DateTime.diff(due, @now) == 10 * 60

      assert %{state: :learning, step: 0, due: due} = Scheduler.review(nil, 1, @now, fuzz: false)
      assert DateTime.diff(due, @now) == 60
    end

    test "easy skips straight to review" do
      assert %{state: :review, due: due} = Scheduler.review(nil, 4, @now, fuzz: false)
      assert DateTime.diff(due, @now, :day) >= 1
    end

    test "graduate after the last learning step" do
      card = apply_review(nil, 3, @now)
      card = apply_review(card, 3, card.due)

      assert card.state == :review
      assert DateTime.diff(card.due, card.last_review_at, :day) >= 1
    end
  end

  test "a lapse sends a review card to relearning" do
    card = apply_review(apply_review(nil, 4, @now), 1, DateTime.add(@now, 8, :day))
    assert card.state == :relearning
  end

  test "preview gives the interval for each rating" do
    assert %{1 => 60, 2 => hard, 3 => 600, 4 => easy} = Scheduler.preview(nil, @now)
    assert hard in 61..599
    assert easy >= 86_400
  end

  test "higher desired retention schedules reviews sooner" do
    card = apply_review(nil, 4, @now)
    later = DateTime.add(card.due, 0)

    low = Scheduler.preview(card, later, desired_retention: 0.8)
    high = Scheduler.preview(card, later, desired_retention: 0.95)
    assert high[3] < low[3]
  end

  test "fuzzing only nudges review intervals" do
    card = apply_review(nil, 4, @now)

    intervals =
      for _ <- 1..30 do
        %{due: due} = Scheduler.review(card, 3, card.due, fuzz: true)
        DateTime.diff(due, card.due, :day)
      end

    unfuzzed = DateTime.diff(Scheduler.review(card, 3, card.due, fuzz: false).due, card.due, :day)
    assert Enum.all?(intervals, &(abs(&1 - unfuzzed) <= max(2, div(unfuzzed, 4))))
  end

  # Any sequence of reviews, at any times, keeps the card in a sane state.
  property "reviews always schedule the card in the future with valid memory state" do
    check all(reviews <- list_of({integer(1..4), integer(-600..(60 * 86_400))}, max_length: 25)) do
      Enum.reduce(reviews, {nil, @now}, fn {rating, offset}, {card, now} ->
        # Review around when the card is due: early, on time or late.
        now = if card, do: max_datetime(now, DateTime.add(card.due, offset)), else: now
        card = apply_review(card, rating, now)

        assert DateTime.after?(card.due, now)
        assert card.stability > 0
        assert card.difficulty >= 1 and card.difficulty <= 10

        {card, DateTime.add(now, 1)}
      end)
    end
  end

  property "better ratings never give shorter intervals" do
    check all(reviews <- list_of({integer(1..4), integer(0..(30 * 86_400))}, max_length: 15)) do
      {card, now} =
        Enum.reduce(reviews, {nil, @now}, fn {rating, offset}, {card, now} ->
          now = if card, do: max_datetime(now, DateTime.add(card.due, offset)), else: now
          {apply_review(card, rating, now), DateTime.add(now, 1)}
        end)

      now = if card, do: max_datetime(now, card.due), else: now
      %{1 => again, 2 => hard, 3 => good, 4 => easy} = Scheduler.preview(card, now)

      assert again <= hard
      assert hard <= good
      assert good <= easy
    end
  end

  defp max_datetime(a, b), do: if(DateTime.after?(a, b), do: a, else: b)
end
