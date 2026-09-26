defmodule Hanguko.Audio.RateLimiterTest do
  use ExUnit.Case, async: true

  alias Hanguko.Audio.RateLimiter

  # Each test gets its own limiter, so the table is never shared between tests
  # and this file can stay async. `start_supervised!/1` stops it afterwards.
  setup do
    name = :"rate_limiter_#{System.unique_integer([:positive])}"
    pid = start_supervised!({RateLimiter, name: name})

    %{limiter: [name: name], now: ~U[2026-09-26 10:30:00Z], pid: pid}
  end

  describe "take/3" do
    test "allows a request under the limit", %{limiter: limiter, now: now} do
      assert :ok == RateLimiter.take(1, now, limiter)
    end

    test "allows exactly the limit within one hour", %{limiter: limiter, now: now} do
      opts = Keyword.put(limiter, :limit, 3)

      assert :ok == RateLimiter.take(1, now, opts)
      assert :ok == RateLimiter.take(1, now, opts)
      assert :ok == RateLimiter.take(1, now, opts)
    end

    test "rejects the request after the limit is spent", %{limiter: limiter, now: now} do
      opts = Keyword.put(limiter, :limit, 3)

      assert :ok == RateLimiter.take(1, now, opts)
      assert :ok == RateLimiter.take(1, now, opts)
      assert :ok == RateLimiter.take(1, now, opts)

      assert {:error, :rate_limited} == RateLimiter.take(1, now, opts)
    end

    # A rejected request must not count, or a user who keeps trying would push
    # their own window further out.
    test "a rejected request doesn't raise the count", %{limiter: limiter, now: now} do
      opts = Keyword.put(limiter, :limit, 3)

      assert :ok == RateLimiter.take(1, now, opts)
      assert :ok == RateLimiter.take(1, now, opts)
      assert :ok == RateLimiter.take(1, now, opts)
      refute :ok == RateLimiter.take(1, now, opts)
      refute :ok == RateLimiter.take(1, now, opts)

      assert [{_key, 3}] = :ets.lookup(Keyword.get(limiter, :name), {1, RateLimiter.window(now)})
    end

    test "counts each user separately", %{limiter: limiter, now: now} do
      assert :ok == RateLimiter.take(1, now, limiter)
      assert :ok == RateLimiter.take(2, now, limiter)
      assert [{_key, 1}] = :ets.lookup(Keyword.get(limiter, :name), {1, RateLimiter.window(now)})
      assert [{_key, 1}] = :ets.lookup(Keyword.get(limiter, :name), {2, RateLimiter.window(now)})
    end

    test "keeps counting within the same hour", %{limiter: limiter, now: now} do
      assert :ok == RateLimiter.take(1, now, limiter)
      assert :ok == RateLimiter.take(1, DateTime.add(now, 15, :minute), limiter)
      assert [{_key, 2}] = :ets.lookup(Keyword.get(limiter, :name), {1, RateLimiter.window(now)})
    end

    test "starts a fresh allowance in the next hour", %{limiter: limiter, now: now} do
      assert :ok == RateLimiter.take(1, now, limiter)
      assert :ok == RateLimiter.take(1, DateTime.add(now, 45, :minute), limiter)
      assert [{_key, 1}] = :ets.lookup(Keyword.get(limiter, :name), {1, RateLimiter.window(now)})
    end

    test "takes the limit from the :limit option over the config", %{limiter: limiter, now: now} do
      opts = Keyword.put(limiter, :limit, 1)
      assert :ok == RateLimiter.take(1, now, opts)
      refute :ok == RateLimiter.take(1, now, opts)
    end
  end

  describe "sweep/2" do
    test "drops counters from windows that have passed", %{limiter: limiter, now: now} do
      hour_from_now = DateTime.add(now, 1, :hour)

      assert :ok == RateLimiter.take(1, now, limiter)
      assert :ok == RateLimiter.take(1, hour_from_now, limiter)

      RateLimiter.sweep(hour_from_now, limiter)

      assert [] == :ets.lookup(Keyword.get(limiter, :name), {1, RateLimiter.window(now)})
    end

    test "keeps the counter for the current window", %{limiter: limiter, now: now} do
      hour_from_now = DateTime.add(now, 1, :hour)

      assert :ok == RateLimiter.take(1, now, limiter)
      assert :ok == RateLimiter.take(1, hour_from_now, limiter)

      RateLimiter.sweep(hour_from_now, limiter)

      assert [{_key, 1}] =
               :ets.lookup(Keyword.get(limiter, :name), {1, RateLimiter.window(hour_from_now)})
    end

    test "is correctly handled and rescheduled when sending message to process", %{
      limiter: limiter,
      now: now,
      pid: pid
    } do
      assert :ok == RateLimiter.take(1, now, limiter)

      send(pid, :sweep)

      # blocks until message processed
      _ = :sys.get_state(pid)

      assert [] == :ets.lookup(Keyword.get(limiter, :name), {1, RateLimiter.window(now)})
    end
  end
end
