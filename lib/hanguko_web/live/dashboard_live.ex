defmodule HangukoWeb.DashboardLive do
  @moduledoc """
  The logged-in home page: what's due today, per deck, and a way in.
  """
  use HangukoWeb, :live_view

  import HangukoWeb.StudyComponents, only: [limit_notice: 1]

  alias Hanguko.SRS

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <.header>
        <.korean class="mr-2 text-primary">오늘</.korean>
        Today
        <:subtitle>{today_message(@summary)}</:subtitle>
        <:actions>
          <.link
            navigate={~p"/study/settings"}
            id="study-settings-link"
            class="-my-1.5 inline-flex items-center gap-1.5 py-1.5 text-sm text-base-content/60 transition hover:text-base-content"
          >
            <.icon name="hero-adjustments-horizontal" class="size-4" /> Study settings
          </.link>
        </:actions>
      </.header>

      <section id="today" class="mt-6 rounded-box border border-base-300 bg-base-100 p-5 sm:p-6">
        <div class="flex flex-wrap items-center justify-between gap-6">
          <dl class="flex gap-6 sm:gap-8">
            <div>
              <dt class="text-sm text-base-content/60">To review</dt>
              <dd id="today-due" class="text-3xl font-bold text-success tabular-nums sm:text-4xl">
                {@summary.due}
              </dd>
            </div>
            <div>
              <dt class="text-sm text-base-content/60">New</dt>
              <dd id="today-new" class="text-3xl font-bold text-secondary tabular-nums sm:text-4xl">
                {@summary.new}
              </dd>
            </div>
            <div>
              <dt class="text-sm text-base-content/60">Studied today</dt>
              <dd id="today-reviewed" class="text-3xl font-bold tabular-nums sm:text-4xl">
                {@summary.reviewed_today}
              </dd>
            </div>
          </dl>
          <%= if @summary.due + @summary.new > 0 do %>
            <.link
              navigate={~p"/study"}
              id="study-now"
              class="inline-flex items-center gap-2 rounded-field bg-primary px-6 py-3 font-semibold text-primary-content shadow-sm transition hover:brightness-110 active:scale-[0.98]"
            >
              Study now <.icon name="hero-arrow-right" class="size-4" />
            </.link>
          <% else %>
            <p id="all-caught-up" class="inline-flex items-center gap-2 font-medium text-success">
              <.icon name="hero-check-circle" class="size-6" /> All caught up
            </p>
          <% end %>
        </div>
        <p :if={@summary.next_learning_due} class="mt-4 text-sm text-base-content/60">
          Cards you're learning come back later today.
        </p>
        <.limit_notice
          id="limit-notice"
          new_limit_reached={@summary.new_limit_reached}
          review_limit_reached={@summary.review_limit_reached}
          settings={@summary.settings}
          class="mt-4"
        />
      </section>

      <section id="my-decks" class="mt-10">
        <h2 class="text-lg font-semibold">My decks</h2>

        <%= if @summary.decks == [] do %>
          <div
            id="no-decks"
            class="mt-3 rounded-box border border-dashed border-base-300 px-6 py-10 text-center"
          >
            <p class="font-medium">You aren't studying any decks yet.</p>
            <p class="mt-1 text-sm text-base-content/60">
              New learners should start with the Hangeul letters, then add vocabulary and phrases.
            </p>
            <div class="mt-5 flex flex-wrap justify-center gap-2">
              <.link
                navigate={~p"/decks?kind=hangeul"}
                class="rounded-field bg-primary px-4 py-2 text-sm font-semibold text-primary-content transition hover:brightness-110"
              >
                Hangeul decks
              </.link>
              <.link
                navigate={~p"/decks"}
                class="rounded-field border border-base-300 px-4 py-2 text-sm font-semibold transition hover:border-base-content/30"
              >
                All decks
              </.link>
            </div>
          </div>
        <% else %>
          <ul class="mt-3 divide-y divide-base-300 overflow-hidden rounded-box border border-base-300 bg-base-100">
            <li
              :for={row <- @summary.decks}
              id={"deck-#{row.deck.id}"}
              class="flex items-center gap-4 px-5 py-3.5"
            >
              <div class="min-w-0 flex-1">
                <.link navigate={~p"/decks/#{row.deck.slug}"} class="font-medium hover:text-primary">
                  {row.deck.title}
                </.link>
                <.korean :if={row.deck.title_ko} class="ml-1.5 text-sm text-base-content/50">
                  {row.deck.title_ko}
                </.korean>
              </div>
              <div class="flex items-center gap-3 text-sm font-semibold tabular-nums">
                <span class="text-success" title="To review">{row.due}</span>
                <span class="text-secondary" title="New">{row.new}</span>
              </div>
              <.link
                :if={row.due + row.new > 0}
                navigate={~p"/study?deck=#{row.deck.slug}"}
                id={"study-deck-#{row.deck.id}"}
                class="rounded-field px-3 py-1.5 text-sm font-medium text-primary transition hover:bg-primary/10"
              >
                Study
              </.link>
            </li>
          </ul>
          <p class="mt-3 text-sm text-base-content/60">
            <.link navigate={~p"/decks"} class="font-medium text-primary hover:underline">Add more decks</.link>
          </p>
        <% end %>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    %{current_scope: scope, settings: settings} = socket.assigns

    {:ok,
     socket
     |> assign(:page_title, "Today")
     |> assign(:summary, SRS.summary(scope, DateTime.utc_now(), settings: settings))}
  end

  defp today_message(%{decks: []}), do: "Add a deck to start studying."
  defp today_message(%{due: 0, new: 0}), do: "You've done everything for today."

  defp today_message(%{due: due, new: new}) do
    "#{format_count(due, "card")} to review and #{format_count(new, "new card")} to learn."
  end
end
