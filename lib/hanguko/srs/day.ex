defmodule Hanguko.SRS.Day do
  @moduledoc """
  Study days. Daily limits reset at a "rollover" hour in the learner's time
  zone (4am by default) rather than at midnight, so a late-night session
  counts toward the day it started in.

  `bounds/3` answers the question in Elixir, for one instant. `study_day/3`
  answers it inside a query, so the database can group and filter many rows
  by study day. Both follow the same rule: take the local wall-clock time and
  move it back by the rollover hour.
  """

  @doc """
  The study day, as a date, that a timestamp column falls on. For use inside
  an Ecto query, where it expands to a SQL fragment:

      import Hanguko.SRS.Day, only: [study_day: 3]

      from l in ReviewLog,
        group_by: study_day(l.reviewed_at, ^timezone, ^rollover_hour)

  `column` must be a `timestamp without time zone` holding UTC, which is how
  Ecto stores `:utc_datetime` fields.

  It is a macro rather than a function because its arguments are query
  expressions (a column, pinned values) that mean nothing outside the query.
  """
  defmacro study_day(column, timezone, rollover_hour) do
    quote do
      fragment(
        "((? AT TIME ZONE 'UTC') AT TIME ZONE ? - make_interval(hours => ?))::date",
        unquote(column),
        unquote(timezone),
        unquote(rollover_hour)
      )
    end
  end

  @doc """
  Returns `{day_start, day_end}` in UTC for the study day containing `now`.

  `day_end` is the start of the next study day.
  """
  def bounds(%DateTime{} = now, timezone, rollover_hour) do
    local = DateTime.shift_zone!(now, timezone)
    today = DateTime.to_date(local)
    date = if local.hour < rollover_hour, do: Date.add(today, -1), else: today

    {start_of(date, timezone, rollover_hour),
     start_of(Date.add(date, 1), timezone, rollover_hour)}
  end

  # The rollover hour can fall into a DST change: take the earlier instant
  # when the hour happens twice, and the first valid one when it is skipped.
  defp start_of(date, timezone, hour) do
    case DateTime.new(date, Time.new!(hour, 0, 0), timezone) do
      {:ok, datetime} -> datetime
      {:ambiguous, first, _second} -> first
      {:gap, _before, just_after} -> just_after
    end
    |> DateTime.shift_zone!("Etc/UTC")
  end
end
