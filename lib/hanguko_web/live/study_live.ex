defmodule HangukoWeb.StudyLive do
  @moduledoc """
  A flashcard study session: shows the next card from the study queue,
  reveals the answer, and records the learner's rating.
  """
  use HangukoWeb, :live_view

  import HangukoWeb.StudyComponents

  alias Hanguko.{Content, SRS}
  alias Hanguko.Content.Item
  alias Hanguko.SRS.Queue

  # Time spent looking at a card is capped (the learner may have walked away).
  @max_duration_ms 60_000
  # Learning cards are shown up to 20 minutes early (see Queue).
  @learn_ahead_ms 20 * 60 * 1000

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div
        id="study"
        phx-hook="StudyKeys"
        data-revealed={to_string(@revealed)}
        data-key={@entry && card_key(@entry)}
        data-can-undo={to_string(!is_nil(@last_log))}
        class="mx-auto max-w-xl"
      >
        <div class="flex items-center justify-between gap-3">
          <.link
            navigate={~p"/dashboard"}
            id="end-session"
            class="inline-flex items-center gap-1 text-sm text-base-content/60 transition hover:text-base-content"
          >
            <.icon name="hero-arrow-left" class="size-4" />
            {if @deck, do: @deck.title, else: "All decks"}
          </.link>
          <div class="flex items-center gap-3">
            <button
              :if={@last_log}
              type="button"
              id="undo"
              phx-click="undo"
              title="Undo last rating (U)"
              class="inline-flex cursor-pointer items-center gap-1 rounded-field px-2 py-1 text-sm text-base-content/60 transition hover:bg-base-200 hover:text-base-content"
            >
              <.icon name="hero-arrow-uturn-left" class="size-4" /> Undo
            </button>
            <.queue_counts counts={@counts} current={@entry && entry_kind(@entry)} />
          </div>
        </div>

        <%= if @entry do %>
          <.flashcard
            entry={@entry}
            revealed={@revealed}
            settings={@settings}
            deck_title={@deck_titles[@entry.item.deck_id]}
          />

          <div class="mt-4">
            <%= if @revealed do %>
              <.rating_buttons intervals={@intervals} card_key={card_key(@entry)} />
            <% else %>
              <button
                type="button"
                id="show-answer"
                phx-click="flip"
                class="flex w-full cursor-pointer items-center justify-center gap-2 rounded-box bg-base-content py-3.5 font-semibold text-base-100 transition hover:opacity-90 active:scale-[0.99]"
              >
                Show answer <kbd class="hidden text-xs font-normal opacity-60 sm:inline">Space</kbd>
              </button>
            <% end %>
          </div>

          <p class="mt-4 hidden text-center text-xs text-base-content/40 sm:block">
            Space shows the answer · 1–4 rate · S plays the sound · U undoes
          </p>
        <% else %>
          <.session_done
            session={@session}
            next_learning_due={@next_learning_due}
            has_decks={@has_decks}
            limits={@limits}
            settings={@settings}
          />
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  attr :entry, :map, required: true
  attr :revealed, :boolean, required: true
  attr :settings, :any, required: true
  attr :deck_title, :string, default: nil

  defp flashcard(assigns) do
    ~H"""
    <section
      id="flashcard"
      class="mt-5 overflow-hidden rounded-box border border-base-300 bg-base-100 shadow-sm"
    >
      <%!-- The deck gives context, e.g. "two" in Sino-Korean vs native numbers --%>
      <p class="px-6 pt-5 text-xs font-semibold tracking-wide text-base-content/40 uppercase">
        <span :if={@deck_title} id="card-deck">{@deck_title} ·</span> {prompt(@entry)}
      </p>

      <div
        id="card-front"
        class="flex min-h-48 flex-col items-center justify-center px-6 py-8 text-center"
      >
        <%= if @entry.template == :recall do %>
          <p class="text-3xl font-semibold text-balance">
            {Enum.join(Item.meanings(@entry.item), ", ")}
          </p>
          <div class="mt-3 flex flex-wrap items-center justify-center gap-2 text-sm text-base-content/50">
            <span :if={@entry.item.part_of_speech}>{@entry.item.part_of_speech}</span>
            <.politeness_badge
              :if={@entry.item.metadata["politeness"]}
              level={@entry.item.metadata["politeness"]}
            />
          </div>
        <% else %>
          <div class="flex items-center gap-2">
            <.korean class="text-6xl leading-tight font-medium">{@entry.item.korean}</.korean>
            <.speak_button
              id="study-speak"
              text={Item.speech_text(@entry.item)}
              rate={@settings.tts_rate}
              size="lg"
              data-primary-speak
            />
          </div>
        <% end %>
      </div>

      <div
        :if={@revealed}
        id="card-answer"
        class="border-t border-base-300 bg-base-200/40 px-6 py-6 text-center"
      >
        <%= cond do %>
          <% @entry.template == :recall -> %>
            <div class="flex items-center justify-center gap-2">
              <.korean class="text-5xl leading-tight font-medium">{@entry.item.korean}</.korean>
              <.speak_button
                id="study-speak"
                text={Item.speech_text(@entry.item)}
                rate={@settings.tts_rate}
                size="lg"
                data-primary-speak
              />
            </div>
            <p
              :if={@settings.show_romanization && @entry.item.romanization}
              class="mt-2 text-secondary"
            >
              {@entry.item.romanization}
            </p>
          <% @entry.item.kind == :jamo -> %>
            <p class="text-3xl font-semibold text-secondary">{@entry.item.romanization}</p>
            <p :if={@entry.item.metadata["name"]} class="mt-2 text-sm text-base-content/60">
              Called
              <.korean class="font-medium text-base-content">{@entry.item.metadata["name"]}</.korean>
            </p>
          <% true -> %>
            <p class="text-2xl font-semibold text-balance">
              {Enum.join(Item.meanings(@entry.item), ", ")}
            </p>
            <p
              :if={@settings.show_romanization && @entry.item.romanization}
              class="mt-2 text-secondary"
            >
              {@entry.item.romanization}
            </p>
        <% end %>

        <div class="mx-auto mt-4 max-w-md space-y-1.5 text-sm text-base-content/70">
          <p :if={@entry.item.metadata["literal"]}>
            Literally: <em>{@entry.item.metadata["literal"]}</em>
          </p>
          <p :if={@entry.item.metadata["example_word"]}>
            As in
            <.korean class="font-medium text-base-content">
              {@entry.item.metadata["example_word"]}
            </.korean>
            ({@entry.item.metadata["example_meaning"]})
          </p>
          <p :if={@entry.item.hint}>{@entry.item.hint}</p>
          <p :if={@entry.item.notes}>{@entry.item.notes}</p>
        </div>
      </div>
    </section>
    """
  end

  attr :session, :map, required: true
  attr :next_learning_due, :any, required: true
  attr :has_decks, :boolean, required: true
  attr :limits, :map, required: true
  attr :settings, :any, required: true

  defp session_done(assigns) do
    ~H"""
    <section
      id="session-done"
      class="mt-8 rounded-box border border-base-300 bg-base-100 px-6 py-10 text-center"
    >
      <%= if @has_decks do %>
        <div class="mx-auto flex size-14 items-center justify-center rounded-full bg-success/15 text-success">
          <.icon name="hero-check" class="size-8" />
        </div>
        <h1 class="mt-4 text-2xl font-bold">{done_title(@session, @limits)}</h1>
        <p class="mt-2 text-base-content/70">
          <%= if @next_learning_due do %>
            Some cards you're learning come back later today. Leave this page open and they'll
            appear when they're due.
          <% else %>
            You're done for today. Come back tomorrow for your next reviews.
          <% end %>
        </p>

        <.limit_notice
          id="limit-notice"
          new_limit_reached={@limits.new_limit_reached}
          review_limit_reached={@limits.review_limit_reached}
          settings={@settings}
          class="mx-auto mt-6 max-w-md"
        />

        <dl
          :if={@session.reviewed > 0}
          id="session-stats"
          class="mx-auto mt-6 grid max-w-sm grid-cols-3 gap-2"
        >
          <div class="rounded-box bg-base-200/60 px-3 py-2">
            <dt class="text-xs text-base-content/60">Cards</dt>
            <dd class="text-xl font-semibold">{@session.reviewed}</dd>
          </div>
          <div class="rounded-box bg-base-200/60 px-3 py-2">
            <dt class="text-xs text-base-content/60">Remembered</dt>
            <dd class="text-xl font-semibold">{remembered_percent(@session)}%</dd>
          </div>
          <div class="rounded-box bg-base-200/60 px-3 py-2">
            <dt class="text-xs text-base-content/60">Minutes</dt>
            <dd class="text-xl font-semibold">{max(round(@session.duration_ms / 60_000), 1)}</dd>
          </div>
        </dl>

        <.link
          navigate={~p"/dashboard"}
          class="mt-8 inline-flex items-center gap-2 rounded-field bg-primary px-5 py-2.5 font-semibold text-primary-content transition hover:brightness-110"
        >
          Back to dashboard
        </.link>
      <% else %>
        <h1 class="text-2xl font-bold">Pick something to study</h1>
        <p class="mt-2 text-base-content/70">
          You aren't studying any decks yet. Add a deck and its cards will show up here.
        </p>
        <.link
          navigate={~p"/decks"}
          class="mt-6 inline-flex items-center gap-2 rounded-field bg-primary px-5 py-2.5 font-semibold text-primary-content transition hover:brightness-110"
        >
          Browse decks
        </.link>
      <% end %>
    </section>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    scope = socket.assigns.current_scope

    settings =
      if connected?(socket),
        do: SRS.put_detected_timezone(scope, get_connect_params(socket)["timezone"]),
        else: SRS.get_settings(scope)

    deck = params["deck"] && Content.get_deck_by_slug(params["deck"])
    enrolled = SRS.list_enrolled_decks(scope)

    socket =
      socket
      |> assign(:page_title, "Study")
      |> assign(:settings, settings)
      |> assign(:deck, deck)
      |> assign(:deck_titles, Map.new(enrolled, &{&1.id, &1.title}))
      |> assign(:has_decks, enrolled != [])
      |> assign(:last_log, nil)
      |> assign(:refresh_timer, nil)
      |> assign(:session, %{
        reviewed: 0,
        ratings: %{1 => 0, 2 => 0, 3 => 0, 4 => 0},
        duration_ms: 0
      })

    {:ok, load_next(socket)}
  end

  @impl true
  def handle_event("flip", _params, socket) do
    {:noreply, assign(socket, :revealed, socket.assigns.entry != nil)}
  end

  def handle_event("rate", %{"rating" => rating, "key" => key}, socket) do
    %{entry: entry, revealed: revealed} = socket.assigns

    with true <- revealed and entry != nil and key == card_key(entry),
         {rating, ""} when rating in 1..4 <- Integer.parse(rating) do
      {:noreply, rate(socket, entry, rating)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("undo", _params, %{assigns: %{last_log: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("undo", _params, socket) do
    %{current_scope: scope, last_log: log, session: session} = socket.assigns

    case SRS.undo_review(scope, log) do
      {:ok, entry} ->
        session = %{
          session
          | reviewed: session.reviewed - 1,
            ratings: Map.update!(session.ratings, log.rating, &(&1 - 1))
        }

        {:noreply,
         socket
         |> assign(:last_log, nil)
         |> assign(:session, session)
         |> assign(:counts, current_queue(socket) |> Queue.counts())
         |> show_entry(entry)}

      {:error, _} ->
        {:noreply,
         socket |> assign(:last_log, nil) |> put_flash(:error, "That rating can't be undone.")}
    end
  end

  @impl true
  def handle_info(:refresh, socket) do
    socket = assign(socket, :refresh_timer, nil)
    {:noreply, if(socket.assigns.entry, do: socket, else: load_next(socket))}
  end

  defp rate(socket, entry, rating) do
    %{current_scope: scope, settings: settings, session: session} = socket.assigns

    duration_ms =
      min(System.monotonic_time(:millisecond) - socket.assigns.shown_at, @max_duration_ms)

    case SRS.review_card(scope, entry, rating, DateTime.utc_now(),
           duration_ms: duration_ms,
           settings: settings
         ) do
      {:ok, log} ->
        session = %{
          session
          | reviewed: session.reviewed + 1,
            ratings: Map.update!(session.ratings, rating, &(&1 + 1)),
            duration_ms: session.duration_ms + duration_ms
        }

        socket |> assign(last_log: log, session: session) |> load_next()

      {:error, :stale} ->
        socket
        |> put_flash(:info, "That card was already studied in another window.")
        |> load_next()
    end
  end

  defp current_queue(socket) do
    %{current_scope: scope, settings: settings, deck: deck} = socket.assigns
    SRS.study_queue(scope, DateTime.utc_now(), settings: settings, deck: deck)
  end

  defp load_next(socket) do
    queue = current_queue(socket)

    socket =
      socket
      |> assign(:counts, Queue.counts(queue))
      |> assign(:next_learning_due, queue.next_learning_due)
      |> assign(:limits, Map.take(queue, [:new_limit_reached, :review_limit_reached]))

    case Queue.next(queue) do
      nil -> socket |> assign(entry: nil, revealed: false) |> schedule_refresh(queue)
      entry -> show_entry(socket, entry)
    end
  end

  defp show_entry(socket, entry) do
    socket
    |> assign(:entry, entry)
    |> assign(:revealed, false)
    |> assign(
      :intervals,
      SRS.preview_intervals(socket.assigns.settings, entry, DateTime.utc_now())
    )
    |> assign(:shown_at, System.monotonic_time(:millisecond))
  end

  # When only learning cards remain for later today, check back when the
  # next one enters the learn-ahead window.
  defp schedule_refresh(socket, %Queue{next_learning_due: nil}), do: socket

  defp schedule_refresh(%{assigns: %{refresh_timer: ref}} = socket, _queue) when ref != nil,
    do: socket

  defp schedule_refresh(socket, %Queue{next_learning_due: due}) do
    if connected?(socket) do
      wait = DateTime.diff(due, DateTime.utc_now(), :millisecond) - @learn_ahead_ms
      ref = Process.send_after(self(), :refresh, wait |> max(1_000) |> min(300_000))
      assign(socket, :refresh_timer, ref)
    else
      socket
    end
  end

  defp card_key(%{item: item, template: template}), do: "#{item.id}-#{template}"

  defp entry_kind(%{card: nil}), do: :new
  defp entry_kind(%{card: %{state: :review}}), do: :review
  defp entry_kind(%{card: _}), do: :learning

  defp prompt(%{template: :recall}), do: "How do you say this in Korean?"
  defp prompt(%{item: %Item{kind: :jamo}}), do: "What sound does this letter make?"
  defp prompt(_entry), do: "What does this mean?"

  defp done_title(%{reviewed: reviewed}, _limits) when reviewed > 0, do: "Nice work!"

  defp done_title(_session, %{new_limit_reached: true}), do: "Daily limit reached"
  defp done_title(_session, %{review_limit_reached: true}), do: "Daily limit reached"
  defp done_title(_session, _limits), do: "Nothing to study right now"

  defp remembered_percent(%{reviewed: reviewed, ratings: ratings}) do
    round((reviewed - ratings[1]) / reviewed * 100)
  end
end
