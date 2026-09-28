defmodule Hanguko.Audio.RateLimiter do
  @moduledoc """
  A fixed-window counter that caps how many clips one user can have
  synthesized per hour.

  This guards the provider bill against a signed-in user holding down a speak
  button or scripting the `audio:speak` event. It is checked by
  `Hanguko.Audio`'s on-demand entry point only when the clip is a miss, so
  replaying audio that already exists costs a user nothing and is never limited.

  The counters live in a public ETS table owned by this process. Callers
  increment it from their own process with an atomic counter update, so a busy
  moment doesn't queue every request behind one GenServer. The process itself
  only owns the table, which must outlive any single request but die with the
  supervisor, and sweeps windows that have passed.

  Counting is per user per clock hour, not a rolling window: a user who spends
  their allowance at 10:59 gets a fresh one at 11:00. Fixed windows let two
  concurrent requests share one atomic increment instead of a read-modify-write
  over a list of timestamps, and the worst case they allow - a full allowance
  either side of a boundary - is bounded and cheap compared to the accounting a
  rolling window needs.

  The limit is deliberately a blunt instrument. The monthly character budget in
  `Hanguko.Audio` is what bounds total spend; this one bounds the rate at which
  a single account can reach it.
  """

  use GenServer

  @sweep_every :timer.hours(1)

  @doc """
  Starts the limiter and its table.

  Options:

    * `:name` - the process and table name, `#{inspect(__MODULE__)}` by default.
      Tests start their own under a unique name so they can run async

  Add it to the supervision tree in `lib/hanguko/application.ex` above the
  endpoint, so no request can arrive before the table exists.
  """
  def start_link(opts \\ []) do
    name = table(opts)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc false
  @impl true
  def init(opts) do
    name = table(opts)

    :ets.new(name, [
      :set,
      :public,
      :named_table,
      write_concurrency: true
    ])

    Process.send_after(self(), :sweep, @sweep_every)

    {:ok, %{table: name}}
  end

  @doc false
  @impl true
  def handle_info(:sweep, state) do
    sweep(DateTime.utc_now(), name: state.table)
    Process.send_after(self(), :sweep, @sweep_every)
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @doc """
  Consumes one of `user_id`'s synthesis slots for the hour containing `now`.

  Returns `:ok` when the request is within the limit, having counted it, or
  `{:error, :rate_limited}` when the allowance for that hour is already spent.
  The count only moves when the answer is `:ok`, so a rejected request doesn't
  push the user further into the hole.

  `now` is passed in rather than read here, matching `Hanguko.SRS.Queue.build/4`
  and friends: the caller owns the clock, and a test can hand over any hour it
  likes without sleeping or mocking time.

  Options:

    * `:limit` - requests allowed per user per hour, defaulting to the
      `:requests_per_user_per_hour` key of the `Hanguko.Audio` config
    * `:name` - which limiter to use, for tests
  """
  def take(user_id, now, opts \\ []) when is_integer(user_id) do
    table = table(opts)
    limit = Keyword.get_lazy(opts, :limit, &configured_limit/0)
    key = {user_id, window(now)}

    # use an "increment, compare, decrement if over limit" strategy
    #
    # {2, 1}:    add 1 to element 2 of the row
    # {key, 0}:  default element to insert if no row
    count = :ets.update_counter(table, key, {2, 1}, {key, 0})

    if count <= limit do
      :ok
    else
      :ets.update_counter(table, key, {2, -1})
      {:error, :rate_limited}
    end
  end

  @doc """
  Deletes counters for every window before the one containing `now`.

  Window keys include the hour, so without this the table would grow by one row
  per active user per hour forever. The process calls this on a timer; it is
  public so a test can drive it directly instead of waiting an hour.
  """
  def sweep(now, opts \\ []) do
    table = table(opts)
    current = window(now)
    :ets.select_delete(table, spec_for_windows_before(current))
  end

  @doc """
  Compute the hourly window for the `now` DateTime object, converted to
  a Unix timestamp.
  """
  def window(now), do: div(DateTime.to_unix(now), 3600)

  defp table(opts) do
    opts[:name] || __MODULE__
  end

  defp spec_for_windows_before(time) do
    [
      {
        # HEAD: pattern shaped like the row. ignore both the user_id
        # and the count, only bind window position
        {{:_, :"$1"}, :_},
        # GUARDS: list of conditions using Erlang-style operators as
        # atoms. In this case, "$1" < time
        [{:<, :"$1", time}],
        # BODY: what to produce for matching row. `true` to delete the
        # row.
        [true]
      }
    ]
  end

  defp configured_limit() do
    :hanguko
    |> Application.fetch_env!(Hanguko.Audio)
    |> Keyword.fetch!(:requests_per_user_per_hour)
  end
end
