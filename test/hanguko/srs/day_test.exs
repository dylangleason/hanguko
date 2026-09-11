defmodule Hanguko.SRS.DayTest do
  use ExUnit.Case, async: true

  alias Hanguko.SRS.Day

  test "a study day runs from the rollover hour to the next one, in local time" do
    # 15:00 in Seoul (UTC+9); the day started at 04:00 KST = 19:00 UTC the day before.
    assert Day.bounds(~U[2026-09-11 06:00:00Z], "Asia/Seoul", 4) ==
             {~U[2026-09-10 19:00:00Z], ~U[2026-09-11 19:00:00Z]}
  end

  test "before the rollover hour it is still the previous study day" do
    # 02:30 in Seoul on the 12th belongs to the study day of the 11th.
    assert Day.bounds(~U[2026-09-11 17:30:00Z], "Asia/Seoul", 4) ==
             {~U[2026-09-10 19:00:00Z], ~U[2026-09-11 19:00:00Z]}

    assert Day.bounds(~U[2026-09-11 19:00:00Z], "Asia/Seoul", 4) ==
             {~U[2026-09-11 19:00:00Z], ~U[2026-09-12 19:00:00Z]}
  end

  test "midnight rollover in UTC" do
    assert Day.bounds(~U[2026-09-11 23:59:59Z], "Etc/UTC", 0) ==
             {~U[2026-09-11 00:00:00Z], ~U[2026-09-12 00:00:00Z]}
  end

  test "days spanning a daylight saving change are 23 or 25 hours long" do
    # US clocks spring forward at 02:00 on 2027-03-14 and fall back at 02:00
    # on 2026-11-01. 01:00 local on those dates still belongs to the study day
    # that started at 04:00 the day before, which contains the change.
    {start, finish} = Day.bounds(~U[2027-03-14 06:00:00Z], "America/New_York", 4)
    assert {start, finish} == {~U[2027-03-13 09:00:00Z], ~U[2027-03-14 08:00:00Z]}
    assert DateTime.diff(finish, start, :hour) == 23

    {start, finish} = Day.bounds(~U[2026-11-01 05:00:00Z], "America/New_York", 4)
    assert {start, finish} == {~U[2026-10-31 08:00:00Z], ~U[2026-11-01 09:00:00Z]}
    assert DateTime.diff(finish, start, :hour) == 25
  end

  test "a rollover hour skipped by a DST change starts at the first valid time" do
    # 02:00 doesn't exist in New York on 2027-03-14.
    {start, _} = Day.bounds(~U[2027-03-14 12:00:00Z], "America/New_York", 2)
    assert start == ~U[2027-03-14 07:00:00Z]
  end
end
