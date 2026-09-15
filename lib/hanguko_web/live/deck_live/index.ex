defmodule HangukoWeb.DeckLive.Index do
  use HangukoWeb, :live_view

  import HangukoWeb.DeckLive.Components

  alias Hanguko.{Content, SRS}

  @filters [nil, :hangeul, :vocab, :phrases]
  @browsable [:hangeul, :vocab, :phrases]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_path={@current_path}
      section={@kind && to_string(@kind)}
    >
      <.header>
        {@page_title}
        <:subtitle>
          Browse the decks and add the ones you want to study. Each deck introduces its cards a few at a time.
        </:subtitle>
      </.header>

      <nav id="deck-filters" class="mt-6 flex flex-wrap gap-1.5" aria-label="Deck type">
        <.link
          :for={kind <- @filters}
          patch={if(kind, do: ~p"/decks?kind=#{kind}", else: ~p"/decks")}
          id={"filter-#{kind || "all"}"}
          aria-current={if(kind == @kind, do: "page")}
          class={[
            "rounded-full border px-3.5 py-1 text-sm font-medium transition",
            if(kind == @kind,
              do: "border-base-content bg-base-content text-base-100",
              else: "border-base-300 bg-base-100 text-base-content/70 hover:border-base-content/30"
            )
          ]}
        >
          {if(kind, do: deck_kind_label(kind), else: "All")}
        </.link>
      </nav>

      <div id="decks" phx-update="stream" class="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <p id="decks-empty" class="hidden text-base-content/60 only:block">No decks here yet.</p>
        <article
          :for={{dom_id, deck} <- @streams.decks}
          id={dom_id}
          class="group relative flex flex-col rounded-box border border-base-300 bg-base-100 p-5 transition hover:-translate-y-0.5 hover:shadow-md"
        >
          <p class="text-xs font-semibold tracking-wide text-base-content/50 uppercase">
            {deck_kind_label(deck.kind)} · Level {deck.level}
          </p>
          <h2 class="mt-1 text-lg font-semibold">
            <.link
              navigate={~p"/decks/#{deck.slug}"}
              class="after:absolute after:inset-0 group-hover:text-primary"
            >
              {deck.title}
            </.link>
          </h2>
          <.korean :if={deck.title_ko} class="text-sm text-base-content/60">
            {deck.title_ko}
          </.korean>
          <p class="mt-3 line-clamp-3 flex-1 text-sm text-base-content/70">{deck.description}</p>
          <div class="mt-4 flex items-center justify-between gap-3">
            <p class="text-xs font-medium text-base-content/50">
              {deck.item_count} {if(deck.item_count == 1, do: "item", else: "items")}
            </p>
            <.enroll_button
              id={"enroll-#{deck.id}"}
              deck={deck}
              enrolled={MapSet.member?(@enrolled, deck.id)}
              current_scope={@current_scope}
            />
          </div>
        </article>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:filters, @filters)
     |> assign(:enrolled, SRS.enrolled_deck_ids(socket.assigns.current_scope))}
  end

  @impl true
  def handle_params(params, _url, socket) do
    kind = parse_kind(params["kind"])

    {:noreply,
     socket
     |> assign(:kind, kind)
     |> assign(:page_title, if(kind, do: deck_kind_label(kind), else: "All decks"))
     # Sentence decks are browsed through the grammar lessons that unlock
     # them, not here.
     |> stream(:decks, Content.list_decks(kind: kind || @browsable), reset: true)}
  end

  @impl true
  def handle_event("toggle_enroll", %{"id" => id}, socket) do
    case socket.assigns.current_scope do
      nil ->
        {:noreply, push_navigate(socket, to: ~p"/users/log-in")}

      scope ->
        deck = Content.get_deck!(id)

        enrolled =
          if MapSet.member?(socket.assigns.enrolled, deck.id) do
            {:ok, _} = SRS.unenroll_deck(scope, deck)
            MapSet.delete(socket.assigns.enrolled, deck.id)
          else
            {:ok, _} = SRS.enroll_deck(scope, deck)
            MapSet.put(socket.assigns.enrolled, deck.id)
          end

        {:noreply, socket |> assign(:enrolled, enrolled) |> stream_insert(:decks, deck)}
    end
  end

  defp parse_kind(kind) when is_binary(kind) do
    Enum.find(@browsable, &(Atom.to_string(&1) == kind))
  end

  defp parse_kind(_), do: nil
end
