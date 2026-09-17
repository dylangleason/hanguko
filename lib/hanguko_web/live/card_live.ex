defmodule HangukoWeb.CardLive do
  @moduledoc """
  The card browser: everything the learner has ever studied, searchable,
  with the three things that can be done to a card — suspend it, put it
  back, or reset it.

  Every filter lives in the query string, so a view of the cards (the
  leeches in one deck, say) can be linked to and comes back on reload. The
  list is capped at `Hanguko.SRS.browse_limit/0` rows with the full count
  alongside it, which keeps a learner with thousands of cards from paying
  for a page they would not read.
  """
  use HangukoWeb, :live_view

  alias Hanguko.Content.Item
  alias Hanguko.SRS
  alias Hanguko.SRS.Card

  @statuses [
    {:all, "All"},
    {:active, "In study"},
    {:suspended, "Suspended"},
    {:leech, "Leeches"}
  ]

  @templates [
    {:recognition, "Recognition"},
    {:recall, "Recall"},
    {:cloze, "Cloze"}
  ]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <.header>
        <.korean class="mr-2 text-primary">카드</.korean>
        Cards
        <:subtitle>
          Every card you've studied, in any deck. Suspend one to take it out of the queue, or
          reset it to learn it again from scratch.
        </:subtitle>
      </.header>

      <.form
        for={@filter_form}
        id="card-filters"
        phx-change="filter"
        class="mt-6 grid gap-3 sm:grid-cols-[minmax(0,1fr)_auto_auto]"
      >
        <.input
          field={@filter_form[:query]}
          type="search"
          label="Search"
          placeholder="Korean, meaning or romanization"
          phx-debounce="300"
          autocomplete="off"
        />
        <.input
          field={@filter_form[:deck]}
          type="select"
          label="Deck"
          options={[{"All decks", ""} | Enum.map(@decks, &{&1.title, &1.slug})]}
        />
        <.input
          field={@filter_form[:template]}
          type="select"
          label="Type"
          options={[{"All types", ""} | Enum.map(@templates, fn {key, label} -> {label, key} end)]}
        />
      </.form>

      <nav id="status-filters" class="mt-4 flex flex-wrap gap-1.5" aria-label="Card status">
        <.filter_pill
          :for={{status, label} <- @statuses}
          id={"status-#{status}"}
          patch={cards_path(@filters, status: status)}
          selected={status == @filters.status}
        >
          {label}
        </.filter_pill>
      </nav>

      <p id="card-count" class="mt-4 text-sm text-base-content/60">
        {count_message(@total, @shown)}
      </p>

      <ul
        id="cards"
        phx-update="stream"
        class="mt-2 divide-y divide-base-300 overflow-hidden rounded-box border border-base-300 bg-base-100"
      >
        <li id="cards-empty" class="hidden px-5 py-10 text-center text-base-content/60 only:block">
          {empty_message(@filters)}
        </li>
        <li
          :for={{dom_id, card} <- @streams.cards}
          id={dom_id}
          class="flex flex-wrap items-start gap-x-4 gap-y-3 px-4 py-4 sm:flex-nowrap sm:px-5"
        >
          <div class="min-w-0 flex-1">
            <div class="flex flex-wrap items-center gap-x-3 gap-y-1">
              <.korean class="text-xl font-medium">{card.item.korean}</.korean>
              <span class="rounded-full bg-base-200 px-2 py-0.5 text-xs font-medium">
                {template_label(card.template)}
              </span>
              <span
                :if={card.suspended}
                id={"suspended-#{card.id}"}
                class="rounded-full bg-warning/15 px-2 py-0.5 text-xs font-medium text-warning"
              >
                Suspended
              </span>
              <span
                :if={Card.leech?(card)}
                id={"leech-#{card.id}"}
                title={"Forgotten #{card.lapses} times"}
                class="rounded-full bg-error/15 px-2 py-0.5 text-xs font-medium text-error"
              >
                Leech
              </span>
            </div>
            <p class="mt-1 text-base-content/80">{Enum.join(Item.meanings(card.item), ", ")}</p>
            <p class="mt-1 text-sm text-base-content/60">
              <.link navigate={~p"/decks/#{card.item.deck.slug}"} class="hover:text-base-content">
                {card.item.deck.title}
              </.link>
              · {state_label(card.state)} · {due_label(card, @now)} · {reviews_label(card)}
            </p>
          </div>

          <div class="flex shrink-0 items-center gap-2">
            <.link
              :if={card.suspended}
              phx-click="unsuspend"
              phx-value-id={card.id}
              id={"unsuspend-#{card.id}"}
              class="cursor-pointer rounded-field border border-base-300 px-3 py-1.5 text-sm font-medium transition hover:border-base-content/30 hover:bg-base-200"
            >
              Unsuspend
            </.link>
            <.link
              :if={!card.suspended}
              phx-click="suspend"
              phx-value-id={card.id}
              id={"suspend-#{card.id}"}
              class="cursor-pointer rounded-field border border-base-300 px-3 py-1.5 text-sm font-medium transition hover:border-base-content/30 hover:bg-base-200"
            >
              Suspend
            </.link>
            <.link
              phx-click="reset"
              phx-value-id={card.id}
              id={"reset-#{card.id}"}
              data-confirm="Reset this card? It goes back to the start of the learning steps. Your review history is kept."
              class="cursor-pointer rounded-field px-3 py-1.5 text-sm font-medium text-base-content/60 transition hover:bg-base-200 hover:text-base-content"
            >
              Reset
            </.link>
          </div>
        </li>
      </ul>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Cards")
     |> assign(:statuses, @statuses)
     |> assign(:templates, @templates)
     |> assign(:now, DateTime.utc_now())
     |> assign(:decks, SRS.list_card_decks(socket.assigns.current_scope))}
  end

  @impl true
  def handle_params(params, _url, socket) do
    filters = %{
      query: normalize_query(params["query"]),
      deck: Enum.find(socket.assigns.decks, &(&1.slug == params["deck"])),
      template: parse_option(params["template"], @templates),
      status: parse_option(params["status"], @statuses) || :all
    }

    {:noreply, socket |> assign(:filters, filters) |> assign_filter_form() |> load_cards()}
  end

  @impl true
  def handle_event("filter", %{"filter" => params}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         cards_path(socket.assigns.filters,
           query: params["query"],
           deck: params["deck"],
           template: params["template"]
         )
     )}
  end

  def handle_event("suspend", %{"id" => id}, socket) do
    act(socket, &SRS.suspend_card(&1, id), "Card suspended. It won't come up in study.")
  end

  def handle_event("unsuspend", %{"id" => id}, socket) do
    act(socket, &SRS.unsuspend_card(&1, id), "Card unsuspended.")
  end

  def handle_event("reset", %{"id" => id}, socket) do
    act(socket, &SRS.reset_card(&1, id), "Card reset. You'll see it again today.")
  end

  # The whole list is reloaded rather than the one row re-streamed: a card
  # that no longer matches the filter (unsuspended while showing only
  # suspended cards) has to leave the list, and the count has to follow.
  defp act(socket, fun, message) do
    case fun.(socket.assigns.current_scope) do
      {:ok, _card} ->
        {:noreply, socket |> put_flash(:info, message) |> load_cards()}

      {:error, :not_found} ->
        {:noreply, socket |> put_flash(:error, "That card is no longer there.") |> load_cards()}
    end
  end

  defp load_cards(socket) do
    %{filters: filters, current_scope: scope} = socket.assigns

    %{cards: cards, total: total} =
      SRS.browse_cards(scope,
        search: filters.query,
        deck_id: filters.deck && filters.deck.id,
        template: filters.template,
        status: filters.status
      )

    socket
    |> assign(:total, total)
    |> assign(:shown, length(cards))
    |> stream(:cards, cards, reset: true)
  end

  defp assign_filter_form(socket) do
    %{query: query, deck: deck, template: template} = socket.assigns.filters

    assign(
      socket,
      :filter_form,
      to_form(
        %{
          "query" => query,
          "deck" => (deck && deck.slug) || "",
          "template" => (template && to_string(template)) || ""
        },
        as: :filter
      )
    )
  end

  # Every filter is a query parameter, so the page can be linked to. Blank
  # values are dropped rather than written out as `?query=`.
  defp cards_path(filters, changes) do
    params =
      %{
        "query" => filters.query,
        "deck" => filters.deck && filters.deck.slug,
        "template" => filters.template,
        "status" => filters.status
      }
      |> Map.merge(Map.new(changes, fn {key, value} -> {to_string(key), value} end))
      |> Enum.reject(fn {_key, value} -> value in [nil, "", :all] end)
      |> Enum.sort()

    ~p"/cards?#{params}"
  end

  # `?query[a]=b` parses to a map, which has no `String.Chars`
  # implementation; treat any non-binary shape as no search at all rather
  # than crashing the LiveView on a crafted query string.
  defp normalize_query(query) when is_binary(query), do: String.trim(query)
  defp normalize_query(_query), do: ""

  defp parse_option(nil, _options), do: nil

  # Never `String.to_atom/1`: the value comes from the query string.
  defp parse_option(value, options) do
    Enum.find_value(options, fn {key, _label} -> to_string(key) == value && key end) || nil
  end

  defp count_message(0, _shown), do: "No cards match."
  defp count_message(1, _shown), do: "1 card."

  defp count_message(total, shown) when total > shown,
    do: "Showing the first #{shown} of #{total} cards. Narrow the search to see the rest."

  defp count_message(total, _shown), do: "#{total} cards."

  defp empty_message(%{status: :leech}),
    do: "No leeches — nothing has been forgotten #{Card.leech_lapses()} times over."

  defp empty_message(%{status: :suspended}), do: "Nothing is suspended."
  defp empty_message(%{query: ""}), do: "No cards yet. They appear here once you study them."
  defp empty_message(_filters), do: "No cards match that search."

  defp template_label(:recognition), do: "Recognition"
  defp template_label(:recall), do: "Recall"
  defp template_label(:cloze), do: "Cloze"

  defp state_label(:learning), do: "Learning"
  defp state_label(:review), do: "In review"
  defp state_label(:relearning), do: "Relearning"

  defp reviews_label(%Card{reps: 1, lapses: 0}), do: "1 review"
  defp reviews_label(%Card{reps: reps, lapses: 0}), do: "#{reps} reviews"

  defp reviews_label(%Card{reps: reps, lapses: lapses}),
    do: "#{reps} reviews, forgotten #{lapses}×"

  # Suspended cards keep the date they had, which would read as a promise to
  # show them; say what is actually true instead.
  defp due_label(%Card{suspended: true}, _now), do: "Out of the queue"

  defp due_label(%Card{due: due}, now) do
    case DateTime.diff(due, now, :day) do
      days when days < -1 -> "#{abs(days)} days overdue"
      days when days < 0 -> "Overdue"
      0 -> "Due today"
      1 -> "Due tomorrow"
      days when days < 30 -> "Due in #{days} days"
      days -> "Due in #{div(days, 30)} months"
    end
  end
end
