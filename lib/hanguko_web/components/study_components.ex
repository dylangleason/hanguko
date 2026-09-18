defmodule HangukoWeb.StudyComponents do
  @moduledoc """
  Components for study sessions and the dashboard.
  """
  use HangukoWeb, :html

  @doc """
  Explains that a daily limit is used up while more cards are waiting, with
  a link to change the limits. Renders nothing when no limit was reached.
  """
  attr :id, :string, required: true
  attr :new_limit_reached, :boolean, required: true
  attr :review_limit_reached, :boolean, required: true
  attr :settings, :any, required: true, doc: "the user's study settings"
  attr :class, :any, default: nil

  def limit_notice(assigns) do
    ~H"""
    <div
      :if={@new_limit_reached or @review_limit_reached}
      id={@id}
      class={[
        "flex gap-3 rounded-box border border-info/30 bg-info/10 px-4 py-3 text-left text-sm",
        @class
      ]}
    >
      <.icon name="hero-information-circle" class="mt-0.5 size-5 shrink-0 text-info" />
      <div class="space-y-1">
        <p :if={@new_limit_reached} id={"#{@id}-new"}>
          You've reached today's limit of {format_count(@settings.daily_new_limit, "new card")}.
          More cards from your decks will be introduced tomorrow.
        </p>
        <p :if={@review_limit_reached} id={"#{@id}-review"}>
          You've reached today's limit of {format_count(@settings.daily_review_limit, "review")}.
          The remaining reviews will wait until tomorrow.
        </p>
        <.link
          navigate={~p"/study/settings"}
          class="inline-block font-medium text-info hover:underline"
        >
          Change daily limits
        </.link>
      </div>
    </div>
    """
  end

  @ratings [
    {1, "Again", "bg-error/10 text-error hover:bg-error/20 focus-visible:ring-error"},
    {2, "Hard", "bg-warning/10 text-warning hover:bg-warning/20 focus-visible:ring-warning"},
    {3, "Good", "bg-success/10 text-success hover:bg-success/20 focus-visible:ring-success"},
    {4, "Easy", "bg-info/10 text-info hover:bg-info/20 focus-visible:ring-info"}
  ]

  @doc """
  The four rating buttons, each labeled with the interval it would give.
  `card_key` identifies the card being rated (see the `StudyKeys` hook).
  """
  attr :intervals, :map, required: true
  attr :card_key, :string, required: true

  attr :suggested, :integer,
    default: nil,
    doc: "a rating to highlight, e.g. from a checked typed answer"

  def rating_buttons(assigns) do
    assigns = assign(assigns, :ratings, @ratings)

    ~H"""
    <div id="rating-buttons" class="grid grid-cols-4 gap-2">
      <button
        :for={{rating, label, colors} <- @ratings}
        type="button"
        id={"rate-#{rating}"}
        phx-click="rate"
        phx-value-rating={rating}
        phx-value-key={@card_key}
        data-suggested={rating == @suggested}
        class={[
          "flex cursor-pointer flex-col items-center rounded-box px-2 py-3 transition active:scale-95",
          "focus-visible:ring-2 focus-visible:outline-none phx-click-loading:opacity-50",
          rating == @suggested && "ring-2 ring-current/40",
          colors
        ]}
      >
        <span class="text-xs font-medium opacity-80">{format_interval(@intervals[rating])}</span>
        <span class="font-semibold">{label}</span>
        <kbd class="mt-1 hidden text-[10px] opacity-60 sm:inline">{rating}</kbd>
      </button>
    </div>
    """
  end

  @doc """
  Remaining card counts: new, learning and review. The kind of the current
  card is underlined.
  """
  attr :counts, :map, required: true
  attr :current, :atom, default: nil

  def queue_counts(assigns) do
    ~H"""
    <div id="queue-counts" class="flex items-center gap-3 text-sm font-semibold tabular-nums">
      <span
        id="count-new"
        title="New"
        class={["text-secondary", @current == :new && "underline underline-offset-4"]}
      >
        {@counts.new}
      </span>
      <span
        id="count-learning"
        title="Learning"
        class={["text-primary", @current == :learning && "underline underline-offset-4"]}
      >
        {@counts.learning}
      </span>
      <span
        id="count-review"
        title="Review"
        class={["text-success", @current == :review && "underline underline-offset-4"]}
      >
        {@counts.review}
      </span>
    </div>
    """
  end

  @doc """
  Formats an interval in seconds compactly: `"1m"`, `"10m"`, `"3h"`, `"4d"`,
  `"2.5mo"`, `"1.2y"`.
  """
  def format_interval(seconds) when is_integer(seconds) do
    cond do
      seconds < 60 -> "<1m"
      seconds < 3600 -> "#{div(seconds, 60)}m"
      seconds < 86_400 -> "#{round(seconds / 3600)}h"
      seconds < 30 * 86_400 -> "#{round(seconds / 86_400)}d"
      seconds < 365 * 86_400 -> "#{decimal(seconds / (30 * 86_400))}mo"
      true -> "#{decimal(seconds / (365 * 86_400))}y"
    end
  end

  defp decimal(value) do
    rounded = Float.round(value, 1)

    if rounded == trunc(rounded),
      do: Integer.to_string(trunc(rounded)),
      else: Float.to_string(rounded)
  end
end
