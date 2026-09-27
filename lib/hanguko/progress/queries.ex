defmodule Hanguko.Progress.Queries do
  @moduledoc """
  The aggregate queries behind `Hanguko.Progress`, built on
  `Hanguko.SRS.Queries`.

  Days are study days, grouped in the database with
  `Hanguko.SRS.Day.study_day/3`. `day` is a `{timezone, rollover_hour}`
  tuple.
  """
  import Ecto.Query, warn: false
  import Hanguko.SRS.Day, only: [study_day: 3]

  alias Hanguko.SRS.Queries, as: SRSQueries

  @doc """
  `%{date: date, reviews: count, duration_ms: total}` for each study day on
  which `user_id` reviewed anything.
  """
  def reviews_by_study_day(user_id, {timezone, hour}) do
    from [log: l] in SRSQueries.review_logs(user_id),
      group_by: selected_as(:date),
      select: %{
        date: selected_as(study_day(l.reviewed_at, ^timezone, ^hour), :date),
        reviews: count(l.id),
        duration_ms: coalesce(sum(l.duration_ms), 0)
      }
  end

  @doc """
  `{reviews, remembered}` for `user_id`'s reviews of cards already in review,
  from the study day `first` on: how many there were, and how many weren't
  rated Again.
  """
  def retention_since(user_id, {timezone, hour}, %Date{} = first) do
    from [log: l] in SRSQueries.of_review_cards(SRSQueries.review_logs(user_id)),
      where: study_day(l.reviewed_at, ^timezone, ^hour) >= type(^first, :date),
      select: {count(l.id), filter(count(l.id), l.rating > 1)}
  end

  @doc """
  `%{date: date, cards: count}` for each study day from `today` to `last` on
  which studied cards (see `Hanguko.SRS.Queries.studied_cards/2`) come due.
  Overdue cards count towards `today`.
  """
  def due_by_study_day(user_id, deck_ids, {timezone, hour}, %Date{} = today, %Date{} = last) do
    from [card: c] in SRSQueries.studied_cards(user_id, deck_ids),
      where: study_day(c.due, ^timezone, ^hour) <= type(^last, :date),
      group_by: selected_as(:date),
      select: %{
        date:
          selected_as(
            fragment("GREATEST(?, ?)", study_day(c.due, ^timezone, ^hour), type(^today, :date)),
            :date
          ),
        cards: count(c.id)
      }
  end

  @doc """
  `%{learning: count, relearning: count, young: count, mature: count,
  suspended: count, total: count}` for `user_id`'s cards of active items,
  whether or not their deck is still enrolled.

  Suspended cards are counted only under `:suspended`. A review card counts
  as `:mature` once `stability` reaches `mature_stability_days`; a missing
  stability counts as 0, so it's `:young`.
  """
  def card_counts(user_id, mature_stability_days) do
    from [card: c] in SRSQueries.active_cards(user_id),
      select: %{
        learning: filter(count(c.id), not c.suspended and c.state == :learning),
        relearning: filter(count(c.id), not c.suspended and c.state == :relearning),
        young:
          filter(
            count(c.id),
            not c.suspended and c.state == :review and
              coalesce(c.stability, 0) < ^mature_stability_days
          ),
        mature:
          filter(
            count(c.id),
            not c.suspended and c.state == :review and
              coalesce(c.stability, 0) >= ^mature_stability_days
          ),
        suspended: filter(count(c.id), c.suspended),
        total: count(c.id)
      }
  end
end
