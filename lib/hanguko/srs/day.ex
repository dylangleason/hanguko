defmodule Hanguko.SRS.Day do
  @moduledoc """
  Study days. Daily limits reset at a "rollover" hour in the learner's time
  zone (4am by default) rather than at midnight, so a late-night session
  counts toward the day it started in.
  """

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
