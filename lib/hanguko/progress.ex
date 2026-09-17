defmodule Hanguko.Progress do
  @moduledoc """
  A learner's progress over time: study streaks, daily activity, recent
  totals, retention, the reviews coming due, and where their cards stand.

  Nothing here is stored. It is all computed from rows the study loop
  already writes — mostly `review_logs`, which keeps every review along
  with the card's state before and after it.

  Days are **study days**: in the learner's time zone, turning over at their
  rollover hour (see `Hanguko.SRS.Day`). A review at 1am counts for the day
  before, just as it does for the daily limits.

  The queries themselves are in `Hanguko.Progress.Queries`.
  """
  alias Hanguko.Accounts.Scope
  alias Hanguko.Progress.Queries
  alias Hanguko.Repo
  alias Hanguko.SRS
  alias Hanguko.SRS.{Day, Settings}
  alias Hanguko.SRS.Queries, as: SRSQueries

  @activity_weeks 26
  @recent_days 30
  @forecast_days 30
  # FSRS stability is the number of days until the chance of recalling a card
  # falls to 90%. Three weeks is the usual line between young and mature.
  @mature_stability_days 21

  @doc "How many weeks of daily activity `overview/2` returns."
  def activity_weeks, do: @activity_weeks

  @doc "How many study days, ending today, the recent totals and retention cover."
  def recent_days, do: @recent_days

  @doc "How many study days, starting today, the forecast covers."
  def forecast_days, do: @forecast_days

  @doc "The stability, in days, from which a review card counts as mature."
  def mature_stability_days, do: @mature_stability_days

  @doc """
  The scope's progress as of `now`.

  Returns a map with:

    * `:today` - the current study day
    * `:streak` - `%{current: days, longest: days, studied_today: boolean}`.
      A streak stays current through the day after the last study day, so
      it isn't lost before the learner has had a chance to study today
    * `:activity` - `%{date: date, reviews: count}` for every study day of
      the last `activity_weeks/0` weeks, starting on a Monday
    * `:recent` - `%{reviews: count, duration_ms: total, days_studied: count}`
      over the last `recent_days/0` study days
    * `:retention` - `%{reviews: count, remembered: count, rate: float | nil}`
      over the same days. Only reviews of cards already in review count
      (see `retention/3`); `rate` is `nil` when there are none
    * `:forecast` - `%{date: date, cards: count}` for each of the next
      `forecast_days/0` study days, starting today. Overdue cards count
      towards today
    * `:cards` - counts of the learner's cards by where they stand:
      `:learning`, `:relearning`, `:young`, `:mature` and `:suspended`
      (suspended cards are counted only there), plus `:total`

  ## Options

    * `:settings` - the user's settings, if already loaded
  """
  def overview(%Scope{user: user} = scope, %DateTime{} = now, opts \\ []) do
    settings = opts[:settings] || SRS.get_settings(scope)
    day = {Settings.timezone(settings), settings.day_rollover_hour}
    today = study_date(now, day)
    days = review_days(user.id, day)

    %{
      today: today,
      streak: streak(Map.keys(days), today),
      activity: activity(days, today),
      recent: recent(days, today),
      retention: retention(user.id, day, today),
      forecast: forecast(user.id, day, today),
      cards: card_counts(user.id)
    }
  end

  defp study_date(now, {timezone, hour}) do
    {day_start, _day_end} = Day.bounds(now, timezone, hour)
    day_start |> DateTime.shift_zone!(timezone) |> DateTime.to_date()
  end

  # %{date => %{reviews: count, duration_ms: total}} for every day with reviews.
  defp review_days(user_id, day) do
    user_id
    |> Queries.reviews_by_study_day(day)
    |> Repo.all()
    |> Map.new(&{&1.date, &1})
  end

  defp streak(dates, today) do
    {last, run, longest} =
      dates
      |> Enum.reject(&Date.after?(&1, today))
      |> Enum.sort(Date)
      |> Enum.reduce({nil, 0, 0}, fn date, {previous, run, longest} ->
        run = if previous && Date.diff(date, previous) == 1, do: run + 1, else: 1
        {date, run, max(longest, run)}
      end)

    current = if last && Date.diff(today, last) <= 1, do: run, else: 0
    %{current: current, longest: longest, studied_today: last == today}
  end

  defp activity(days, today) do
    first = today |> Date.add(-7 * (@activity_weeks - 1)) |> Date.beginning_of_week()

    for date <- Date.range(first, today) do
      %{date: date, reviews: get_in(days, [date, :reviews]) || 0}
    end
  end

  defp recent(days, today) do
    first = Date.add(today, 1 - @recent_days)

    in_window =
      for {date, day} <- days,
          not Date.before?(date, first) and not Date.after?(date, today),
          do: day

    %{
      reviews: Enum.sum_by(in_window, & &1.reviews),
      duration_ms: Enum.sum_by(in_window, & &1.duration_ms),
      days_studied: length(in_window)
    }
  end

  # True retention: of the reviews of cards that were already in review, the
  # share not rated Again. Learning steps are left out, because missing a
  # card first seen ten minutes ago says little about long-term memory.
  defp retention(user_id, day, today) do
    first = Date.add(today, 1 - @recent_days)
    {reviews, remembered} = user_id |> Queries.retention_since(day, first) |> Repo.one()

    %{reviews: reviews, remembered: remembered, rate: if(reviews > 0, do: remembered / reviews)}
  end

  # Counts what the queue would show: the same decks, and the same cards.
  defp forecast(user_id, day, today) do
    last = Date.add(today, @forecast_days - 1)
    deck_ids = user_id |> SRSQueries.studied_deck_ids() |> Repo.all()

    due =
      user_id
      |> Queries.due_by_study_day(deck_ids, day, today, last)
      |> Repo.all()
      |> Map.new(&{&1.date, &1.cards})

    for date <- Date.range(today, last), do: %{date: date, cards: Map.get(due, date, 0)}
  end

  # Every card the learner has, whether or not its deck is still enrolled,
  # except those of retired content.
  defp card_counts(user_id) do
    cards = user_id |> Queries.card_standings() |> Repo.all()

    {suspended, active} = Enum.split_with(cards, & &1.suspended)
    {mature, young} = active |> Enum.filter(&(&1.state == :review)) |> Enum.split_with(&mature?/1)

    %{
      learning: Enum.count(active, &(&1.state == :learning)),
      relearning: Enum.count(active, &(&1.state == :relearning)),
      young: length(young),
      mature: length(mature),
      suspended: length(suspended),
      total: length(cards)
    }
  end

  defp mature?(%{stability: stability}), do: (stability || 0) >= @mature_stability_days
end
