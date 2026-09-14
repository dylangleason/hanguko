defmodule Hanguko.ProgressTest do
  use Hanguko.DataCase, async: true

  import Hanguko.AccountsFixtures
  import Hanguko.ContentFixtures
  import Hanguko.SRSFixtures

  alias Hanguko.{Progress, SRS}

  # Noon in Seoul on Tuesday 15 September 2026.
  @now ~U[2026-09-15 03:00:00Z]

  # A wall-clock time in Seoul, as a UTC timestamp.
  defp seoul(date, hour, minute \\ 0) do
    date
    |> DateTime.new!(Time.new!(hour, minute, 0), "Asia/Seoul")
    |> DateTime.shift_zone!("Etc/UTC")
  end

  setup do
    scope = user_scope_fixture()
    {:ok, _} = SRS.update_settings(scope, %{timezone: "Asia/Seoul", day_rollover_hour: 4})
    deck = deck_fixture()
    SRS.enroll_deck(scope, deck)
    card = card_fixture(scope.user, item_fixture(deck), due: seoul(~D[2026-09-15], 20))

    %{scope: scope, user: scope.user, deck: deck, card: card}
  end

  test "a learner with no history gets empty progress" do
    overview = Progress.overview(user_scope_fixture(), @now)

    assert overview.streak == %{current: 0, longest: 0, studied_today: false}
    assert overview.recent == %{reviews: 0, duration_ms: 0, days_studied: 0}
    assert overview.retention == %{reviews: 0, remembered: 0, rate: nil}
    assert Enum.all?(overview.activity, &(&1.reviews == 0))
    assert Enum.all?(overview.forecast, &(&1.cards == 0))
    assert overview.cards.total == 0
  end

  describe "streaks" do
    test "count consecutive study days, which turn over at the rollover hour", %{
      scope: scope,
      user: user,
      card: card
    } do
      # Four days in a row earlier in the month...
      for day <- 1..4, do: review_log_fixture(user, card, seoul(Date.new!(2026, 9, day), 12))

      # ...and three ending today: 3:30am on the 14th still belongs to the 13th.
      review_log_fixture(user, card, seoul(~D[2026-09-14], 3, 30))
      review_log_fixture(user, card, seoul(~D[2026-09-14], 23, 30))
      review_log_fixture(user, card, seoul(~D[2026-09-15], 10, 30))

      # Another learner's review on the 12th doesn't bridge the gap.
      review_log_fixture(user_scope_fixture().user, card, seoul(~D[2026-09-12], 12))

      assert Progress.overview(scope, @now).streak ==
               %{current: 3, longest: 4, studied_today: true}
    end

    test "stay current until the end of the day after the last study day", %{
      scope: scope,
      user: user,
      card: card
    } do
      review_log_fixture(user, card, seoul(~D[2026-09-14], 20))

      assert %{current: 1, studied_today: false} = Progress.overview(scope, @now).streak

      # 3:59am on Wednesday is still Tuesday's study day...
      assert %{current: 1} = Progress.overview(scope, seoul(~D[2026-09-16], 3, 59)).streak

      # ...and at 4am the streak is over.
      assert %{current: 0, longest: 1} =
               Progress.overview(scope, seoul(~D[2026-09-16], 4)).streak
    end
  end

  test "activity counts reviews per study day for the last 26 weeks, from a Monday", %{
    scope: scope,
    user: user,
    card: card
  } do
    review_log_fixture(user, card, seoul(~D[2026-09-15], 9))
    review_log_fixture(user, card, seoul(~D[2026-09-15], 10))
    review_log_fixture(user, card, seoul(~D[2026-09-10], 9))
    # Before the window
    review_log_fixture(user, card, seoul(~D[2026-01-05], 9))

    activity = Progress.overview(scope, @now).activity
    first = hd(activity).date

    assert Date.day_of_week(first) == 1
    assert Date.diff(~D[2026-09-15], first) in (7 * 25)..(7 * 26 - 1)
    assert length(activity) == Date.diff(~D[2026-09-15], first) + 1
    assert List.last(activity) == %{date: ~D[2026-09-15], reviews: 2}
    assert Enum.find(activity, &(&1.date == ~D[2026-09-10])).reviews == 1
    assert Enum.sum_by(activity, & &1.reviews) == 3
  end

  test "recent totals and retention cover the last 30 study days", %{
    scope: scope,
    user: user,
    card: card
  } do
    for rating <- [1, 3, 4, 3] do
      review_log_fixture(user, card, seoul(~D[2026-09-10], 9),
        rating: rating,
        duration_ms: 60_000
      )
    end

    # A learning step is a review, but doesn't count towards retention.
    review_log_fixture(user, card, seoul(~D[2026-09-11], 9),
      state_before: :learning,
      rating: 1,
      duration_ms: 30_000
    )

    # The 31st study day back is outside the window.
    review_log_fixture(user, card, seoul(~D[2026-08-16], 9), rating: 1)

    overview = Progress.overview(scope, @now)

    assert overview.recent == %{reviews: 5, duration_ms: 270_000, days_studied: 2}
    assert overview.retention == %{reviews: 4, remembered: 3, rate: 0.75}
  end

  test "the forecast counts the cards the queue will show over the next 30 days", %{
    scope: scope,
    user: user,
    deck: deck
  } do
    due = fn date, hour, attrs ->
      card_fixture(user, item_fixture(deck), Map.merge(%{due: seoul(date, hour)}, attrs))
    end

    # With the setup card due tonight, three cards count for today: that one,
    # an overdue card, and one due at 2am, which is still today's study day.
    due.(~D[2026-09-12], 9, %{})
    due.(~D[2026-09-16], 2, %{})
    due.(~D[2026-09-18], 9, %{})
    due.(~D[2026-10-14], 9, %{})

    # Past the last day of the forecast
    due.(~D[2026-10-15], 9, %{})

    # Cards the queue won't show
    due.(~D[2026-09-15], 9, %{suspended: true})
    card_fixture(user, item_fixture(deck, retired: true), due: seoul(~D[2026-09-15], 9))
    card_fixture(user, item_fixture(deck_fixture()), due: seoul(~D[2026-09-15], 9))

    forecast = Progress.overview(scope, @now).forecast

    assert length(forecast) == 30
    assert hd(forecast) == %{date: ~D[2026-09-15], cards: 3}
    assert List.last(forecast) == %{date: ~D[2026-10-14], cards: 1}
    assert Enum.find(forecast, &(&1.date == ~D[2026-09-18])).cards == 1
    assert Enum.sum_by(forecast, & &1.cards) == 5
  end

  test "cards are counted by where they stand, with mature review cards apart", %{
    scope: scope,
    user: user,
    deck: deck
  } do
    # The setup card is a young review card.
    card_fixture(user, item_fixture(deck), state: :learning, stability: 0.5)
    card_fixture(user, item_fixture(deck), state: :relearning)
    card_fixture(user, item_fixture(deck), stability: 21.0)
    card_fixture(user, item_fixture(deck), stability: 40.0, suspended: true)

    # Not counted: retired content and other learners' cards
    card_fixture(user, item_fixture(deck, retired: true))
    card_fixture(user_scope_fixture().user, item_fixture(deck))

    assert Progress.overview(scope, @now).cards ==
             %{learning: 1, relearning: 1, young: 1, mature: 1, suspended: 1, total: 5}
  end
end
