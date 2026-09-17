defmodule HangukoWeb.StatsLive do
  @moduledoc """
  A learner's progress: their streak, recent totals and retention, a heatmap
  of daily reviews, the reviews coming due, and where their cards stand.
  The numbers come from `Hanguko.Progress`.

  Both charts are single-series. Each mark has a hover title, and each
  chart has a table view.
  """
  use HangukoWeb, :live_view

  alias Hanguko.Progress

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <.header>
        <.korean class="mr-2 text-primary">기록</.korean>
        Progress
        <:subtitle>{streak_message(@overview.streak)}</:subtitle>
      </.header>

      <%= if @has_history do %>
        <dl id="stats" class="mt-6 grid grid-cols-2 gap-3 lg:grid-cols-4">
          <.stat
            id="stat-streak"
            label="Current streak"
            value={days(@overview.streak.current)}
            note={"Longest: #{days(@overview.streak.longest)}"}
          />
          <.stat
            id="stat-reviews"
            label={"Reviews, last #{Progress.recent_days()} days"}
            value={format_number(@overview.recent.reviews)}
            note={"On #{days(@overview.recent.days_studied)}"}
          />
          <.stat
            id="stat-retention"
            label="Retention"
            value={percent(@overview.retention.rate)}
            note={retention_note(@overview.retention)}
          />
          <.stat
            id="stat-time"
            label={"Time studied, last #{Progress.recent_days()} days"}
            value={duration(@overview.recent.duration_ms)}
            note={time_note(@overview.recent)}
          />
        </dl>

        <section id="activity" class="mt-6 rounded-box border border-base-300 bg-base-100 p-5">
          <div class="flex flex-wrap items-baseline justify-between gap-2">
            <h2 class="font-semibold">Daily reviews</h2>
            <p class="text-sm text-base-content/60">Last {Progress.activity_weeks()} weeks</p>
          </div>

          <div class="mt-4 overflow-x-auto pb-1">
            <div class="inline-flex gap-2">
              <div
                class="grid grid-rows-7 gap-[2px] text-[10px] leading-3 text-base-content/50"
                aria-hidden="true"
              >
                <span :for={weekday <- 1..7} class="h-3">{weekday_label(weekday)}</span>
              </div>
              <div
                id="activity-grid"
                class="grid grid-flow-col grid-rows-7 gap-[2px]"
                role="img"
                aria-label={activity_label(@overview.activity)}
              >
                <div
                  :for={day <- @overview.activity}
                  id={"day-#{day.date}"}
                  title={day_title(day)}
                  class={["size-3 rounded-[2px]", heat_class(day.reviews, @busiest_day)]}
                >
                </div>
              </div>
            </div>
          </div>

          <div
            class="mt-3 flex items-center justify-end gap-1 text-xs text-base-content/60"
            aria-hidden="true"
          >
            Less
            <span
              :for={reviews <- [0, 1, 2, 3]}
              class={["size-3 rounded-[2px]", heat_class(reviews, 3)]}
            ></span>
            More
          </div>

          <details id="activity-table" class="mt-3 text-sm">
            <summary class="cursor-pointer text-base-content/60 hover:text-base-content">
              Show as a table
            </summary>
            <table class="mt-2 w-full max-w-xs">
              <thead class="text-left text-xs text-base-content/50">
                <tr>
                  <th class="py-1 font-medium">Day</th>
                  <th class="py-1 text-right font-medium">Reviews</th>
                </tr>
              </thead>
              <tbody class="tabular-nums">
                <tr :for={day <- Enum.reverse(@overview.activity)} :if={day.reviews > 0}>
                  <td class="py-0.5">{date_label(day.date)}</td>
                  <td class="py-0.5 text-right">{day.reviews}</td>
                </tr>
              </tbody>
            </table>
            <p class="mt-1 text-xs text-base-content/50">Days not listed had no reviews.</p>
          </details>
        </section>

        <section id="forecast" class="mt-6 rounded-box border border-base-300 bg-base-100 p-5">
          <div class="flex flex-wrap items-baseline justify-between gap-2">
            <h2 class="font-semibold">Coming due</h2>
            <p class="text-sm text-base-content/60">Next {Progress.forecast_days()} days</p>
          </div>

          <%= if @forecast_peak == 0 do %>
            <p id="forecast-empty" class="mt-3 text-sm text-base-content/60">
              Nothing is scheduled in the next {Progress.forecast_days()} days.
            </p>
          <% else %>
            <.forecast_chart forecast={@overview.forecast} axis_max={@axis_max} peak={@forecast_peak} />

            <details id="forecast-table" class="mt-3 text-sm">
              <summary class="cursor-pointer text-base-content/60 hover:text-base-content">
                Show as a table
              </summary>
              <table class="mt-2 w-full max-w-xs">
                <thead class="text-left text-xs text-base-content/50">
                  <tr>
                    <th class="py-1 font-medium">Day</th>
                    <th class="py-1 text-right font-medium">Cards due</th>
                  </tr>
                </thead>
                <tbody class="tabular-nums">
                  <tr :for={day <- @overview.forecast} :if={day.cards > 0}>
                    <td class="py-0.5">{date_label(day.date)}</td>
                    <td class="py-0.5 text-right">{day.cards}</td>
                  </tr>
                </tbody>
              </table>
              <p class="mt-1 text-xs text-base-content/50">
                Overdue cards count towards today. Days not listed have nothing due.
              </p>
            </details>
          <% end %>
        </section>

        <section id="cards-by-state" class="mt-6 rounded-box border border-base-300 bg-base-100 p-5">
          <div class="flex flex-wrap items-baseline justify-between gap-2">
            <h2 class="font-semibold">Your cards</h2>
            <p class="text-sm text-base-content/60">{format_number(@overview.cards.total)} in all</p>
          </div>
          <dl class="mt-4 grid grid-cols-2 gap-x-6 gap-y-4 sm:grid-cols-3 lg:grid-cols-5">
            <div :for={{key, label, note} <- card_states()} id={"cards-#{key}"}>
              <dt class="text-sm text-base-content/60">{label}</dt>
              <dd class="text-2xl font-semibold">{format_number(@overview.cards[key])}</dd>
              <dd class="mt-0.5 text-xs text-base-content/50">{note}</dd>
            </div>
          </dl>
        </section>
      <% else %>
        <section
          id="no-progress"
          class="mt-6 rounded-box border border-dashed border-base-300 px-6 py-10 text-center"
        >
          <p class="font-medium">Nothing to show yet.</p>
          <p class="mt-1 text-sm text-base-content/60">
            Study a few cards and your streak, reviews and upcoming workload will appear here.
          </p>
          <.link
            navigate={~p"/dashboard"}
            class="mt-5 inline-flex rounded-field bg-primary px-4 py-2 text-sm font-semibold text-primary-content transition hover:brightness-110"
          >
            Go to today's study
          </.link>
        </section>
      <% end %>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :note, :string, default: nil

  defp stat(assigns) do
    ~H"""
    <div id={@id} class="rounded-box border border-base-300 bg-base-100 px-4 py-3.5">
      <dt class="text-sm text-base-content/60">{@label}</dt>
      <dd class="mt-1 text-3xl font-semibold">{@value}</dd>
      <dd :if={@note} class="mt-0.5 text-xs text-base-content/60">{@note}</dd>
    </div>
    """
  end

  attr :forecast, :list, required: true
  attr :axis_max, :integer, required: true
  attr :peak, :integer, required: true

  # A column per day: columns grow from the baseline, capped at 24px wide
  # with 2px between them and rounded tops. Only the busiest day is labelled;
  # the axis, titles and table carry the rest.
  defp forecast_chart(assigns) do
    assigns =
      assign(assigns, :peak_date, Enum.find(assigns.forecast, &(&1.cards == assigns.peak)).date)

    ~H"""
    <div id="forecast-chart" class="mt-4 grid grid-cols-[auto_minmax(0,1fr)] gap-x-2">
      <div
        class="relative h-40 w-6 text-right text-[11px] text-base-content/50 tabular-nums"
        aria-hidden="true"
      >
        <span class="absolute top-0 right-0 -translate-y-1/2">{@axis_max}</span>
        <span class="absolute top-1/2 right-0 -translate-y-1/2">{div(@axis_max, 2)}</span>
        <span class="absolute right-0 bottom-0 translate-y-1/2">0</span>
      </div>

      <div class="relative h-40">
        <div class="absolute inset-x-0 top-0 border-t border-base-300"></div>
        <div class="absolute inset-x-0 top-1/2 border-t border-base-300"></div>
        <div class="absolute inset-x-0 bottom-0 border-t border-base-300"></div>

        <div class="absolute inset-0 flex items-end gap-[2px]">
          <div
            :for={day <- @forecast}
            id={"due-#{day.date}"}
            title={due_title(day)}
            class="relative flex h-full min-w-0 flex-1 items-end justify-center"
          >
            <div
              :if={day.cards > 0}
              class="w-full max-w-6 rounded-t-[4px] bg-secondary"
              style={"height: #{column_height(day.cards, @axis_max)}%"}
            >
            </div>
            <span
              :if={day.date == @peak_date}
              id="forecast-peak"
              class="absolute text-xs font-medium whitespace-nowrap text-base-content/70"
              style={"bottom: calc(#{column_height(day.cards, @axis_max)}% + 2px)"}
            >
              {day.cards}
            </span>
          </div>
        </div>
      </div>

      <div></div>
      <div class="mt-1.5 flex h-4 gap-[2px] text-[11px] text-base-content/50" aria-hidden="true">
        <span
          :for={{day, index} <- Enum.with_index(@forecast)}
          class="relative min-w-0 flex-1 whitespace-nowrap"
        >
          <span :if={rem(index, 7) == 0} class="absolute left-0">
            {if index == 0, do: "Today", else: short_date(day.date)}
          </span>
        </span>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    %{current_scope: scope, settings: settings} = socket.assigns

    overview = Progress.overview(scope, DateTime.utc_now(), settings: settings)
    forecast_peak = overview.forecast |> Enum.map(& &1.cards) |> Enum.max()

    {:ok,
     socket
     |> assign(:page_title, "Progress")
     |> assign(:overview, overview)
     |> assign(:has_history, overview.streak.longest > 0 or overview.cards.total > 0)
     |> assign(:busiest_day, overview.activity |> Enum.map(& &1.reviews) |> Enum.max())
     |> assign(:forecast_peak, forecast_peak)
     |> assign(:axis_max, axis_max(forecast_peak))}
  end

  defp card_states do
    [
      {:learning, "Learning", "In their first learning steps"},
      {:relearning, "Relearning", "Forgotten and being relearned"},
      {:young, "Young",
       "In review, remembered for under #{Progress.mature_stability_days()} days"},
      {:mature, "Mature", "Remembered for #{Progress.mature_stability_days()} days or more"},
      {:suspended, "Suspended", "Set aside from study"}
    ]
  end

  defp streak_message(%{current: 0, longest: 0}),
    do: "Your streak, reviews and upcoming workload."

  defp streak_message(%{studied_today: true, current: current}),
    do: "You've studied today — #{days(current)} in a row."

  defp streak_message(%{current: 0}), do: "Study today to start a new streak."

  defp streak_message(%{current: current}),
    do: "Study today to keep your #{current}-day streak going."

  defp retention_note(%{rate: nil}), do: "Shown once you review cards you've learned"

  defp retention_note(%{reviews: reviews, remembered: remembered}),
    do: "#{format_number(remembered)} of #{format_number(reviews)} reviews remembered"

  defp time_note(%{days_studied: 0}), do: nil

  defp time_note(%{duration_ms: ms, days_studied: days}),
    do: "About #{duration(div(ms, days))} a day"

  # One hue, more is stronger: three steps relative to the busiest day, and a
  # neutral cell for days without reviews. Three is as many as the primary
  # colour allows while each step stays distinct from the next and the
  # lightest still stands out from the card, in both themes (checked with
  # the dataviz ordinal-ramp validator).
  defp heat_class(0, _busiest), do: "bg-base-300"

  defp heat_class(reviews, busiest) do
    case ceil(3 * reviews / busiest) do
      1 -> "bg-primary/60"
      2 -> "bg-primary/80"
      _ -> "bg-primary"
    end
  end

  defp activity_label(activity) do
    total = Enum.sum_by(activity, & &1.reviews)
    studied = Enum.count(activity, &(&1.reviews > 0))

    "#{format_number(total)} reviews over #{days(studied)} in the last #{Progress.activity_weeks()} weeks"
  end

  defp weekday_label(1), do: "Mon"
  defp weekday_label(3), do: "Wed"
  defp weekday_label(5), do: "Fri"
  defp weekday_label(_), do: ""

  defp day_title(%{date: date, reviews: reviews}),
    do: "#{format_count(reviews, "review")} · #{date_label(date)}"

  defp due_title(%{date: date, cards: cards}),
    do: "#{format_count(cards, "card")} due · #{date_label(date)}"

  # The axis tops out at a round number at or above the busiest day, and
  # always divides evenly in two for the middle gridline.
  defp axis_max(peak) do
    Stream.iterate(1, &(&1 * 10))
    |> Stream.flat_map(&[2 * &1, 4 * &1, 6 * &1, 8 * &1, 10 * &1])
    |> Enum.find(&(&1 >= peak))
  end

  defp column_height(cards, axis_max), do: Float.round(cards / axis_max * 100, 2)

  defp date_label(date), do: "#{Calendar.strftime(date, "%a")} #{short_date(date)}"
  defp short_date(date), do: "#{date.day} #{Calendar.strftime(date, "%b")}"

  defp days(1), do: format_count(1, "day")
  defp days(n), do: format_count(n, "day")

  defp percent(nil), do: "—"
  defp percent(rate), do: "#{round(rate * 100)}%"

  defp duration(ms) do
    case div(ms, 60_000) do
      minutes when minutes < 60 -> "#{minutes} min"
      minutes -> "#{div(minutes, 60)} h #{rem(minutes, 60)} min"
    end
  end
end
