defmodule HangukoWeb.PhraseLive do
  @moduledoc """
  Everyday phrases, grouped by the situation you'd use them in.

  Each situation is a `phrases` deck. Visitors pick a situation, narrow it
  to one speech level, listen, and add the situation to their studies,
  which enrols its deck. Phrases linked by `variant_of` are shown with each
  other, so the polite and casual forms of a phrase are seen side by side.
  """
  use HangukoWeb, :live_view

  import HangukoWeb.DeckLive.Components

  alias Hanguko.{Content, SRS}
  alias Hanguko.Content.Item

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Phrases
        <.korean class="ml-1 font-medium text-base-content/50">표현</.korean>
        <:subtitle>
          Ready-made phrases for everyday situations. The badge on each phrase says who you can say
          it to: formal for strangers and work, polite for most people, casual only for close
          friends.
        </:subtitle>
      </.header>

      <%= if @deck do %>
        <div class="mt-8 grid items-start gap-6 md:grid-cols-[13rem_minmax(0,1fr)] md:gap-8">
          <nav
            id="situations"
            aria-label="Situations"
            class="-mx-4 flex gap-1.5 overflow-x-auto px-4 pb-1 md:sticky md:top-20 md:mx-0 md:flex-col md:overflow-visible md:px-0 md:pb-0"
          >
            <.link
              :for={deck <- @decks}
              patch={phrases_path(deck, @politeness)}
              id={"situation-#{deck.slug}"}
              aria-current={if(deck.id == @deck.id, do: "page")}
              class={[
                "flex shrink-0 items-center justify-between gap-2 rounded-field px-3 py-2 text-sm transition",
                if(deck.id == @deck.id,
                  do: "bg-base-content font-semibold text-base-100",
                  else: "text-base-content/70 hover:bg-base-200 hover:text-base-content"
                )
              ]}
            >
              <span>{deck.title}</span>
              <span :if={MapSet.member?(@enrolled, deck.id)} id={"studying-#{deck.slug}"}>
                <.icon name="hero-check-circle" class="size-4 opacity-70" />
                <span class="sr-only">(studying)</span>
              </span>
            </.link>
          </nav>

          <section id="situation" class="min-w-0">
            <div class="flex flex-wrap items-start justify-between gap-4">
              <div class="min-w-0">
                <h2 class="text-2xl font-bold tracking-tight">
                  {@deck.title}
                  <.korean :if={@deck.title_ko} class="ml-1 text-xl font-medium text-base-content/50">
                    {@deck.title_ko}
                  </.korean>
                </h2>
                <p class="mt-1 max-w-2xl text-base-content/70">{@deck.description}</p>
              </div>
              <div class="flex items-center gap-2">
                <.link
                  :if={MapSet.member?(@enrolled, @deck.id)}
                  navigate={~p"/study?deck=#{@deck.slug}"}
                  id="study-situation"
                  class="inline-flex items-center gap-1.5 rounded-field bg-primary px-3 py-1.5 text-sm font-medium text-primary-content shadow-sm transition hover:brightness-110"
                >
                  Study now <.icon name="hero-arrow-right" class="size-4" />
                </.link>
                <.enroll_button
                  id="enroll"
                  deck={@deck}
                  enrolled={MapSet.member?(@enrolled, @deck.id)}
                  current_scope={@current_scope}
                />
              </div>
            </div>

            <div class="mt-5 flex flex-wrap items-center justify-between gap-3">
              <nav id="politeness-filters" class="flex flex-wrap gap-1.5" aria-label="Speech level">
                <.link
                  :for={level <- @levels}
                  patch={phrases_path(@deck, level)}
                  id={"politeness-#{level || "all"}"}
                  aria-current={if(level == @politeness, do: "page")}
                  class={[
                    "rounded-full border px-3.5 py-1 text-sm font-medium transition",
                    if(level == @politeness,
                      do: "border-base-content bg-base-content text-base-100",
                      else:
                        "border-base-300 bg-base-100 text-base-content/70 hover:border-base-content/30"
                    )
                  ]}
                >
                  {level_label(level)}
                </.link>
              </nav>
              <div class="flex flex-wrap gap-2">
                <.reveal_toggle
                  id="toggle-romanization"
                  target="#phrases"
                  class_name="hide-romanization"
                >
                  Hide romanization
                </.reveal_toggle>
                <.reveal_toggle id="toggle-meaning" target="#phrases" class_name="hide-meaning">
                  Hide meanings
                </.reveal_toggle>
              </div>
            </div>

            <ul
              id="phrases"
              phx-update="stream"
              class="mt-4 divide-y divide-base-300 overflow-hidden rounded-box border border-base-300 bg-base-100"
            >
              <li id="phrases-empty" class="hidden px-5 py-6 text-base-content/60 only:block">
                No {String.downcase(level_label(@politeness))} phrases for this situation.
              </li>
              <li
                :for={{dom_id, item} <- @streams.phrases}
                id={dom_id}
                class="flex items-start gap-3 px-4 py-4 sm:gap-4 sm:px-5"
              >
                <.speak_button
                  id={"#{dom_id}-speak"}
                  text={Item.speech_text(item)}
                  rate={@tts_rate}
                  class="mt-0.5"
                />
                <div class="min-w-0 flex-1">
                  <div class="flex flex-wrap items-center gap-x-3 gap-y-1">
                    <.korean class="text-2xl font-medium">{item.korean}</.korean>
                    <.politeness_badge
                      :if={item.metadata["politeness"]}
                      level={item.metadata["politeness"]}
                    />
                  </div>
                  <p :if={item.romanization} class="romanization mt-0.5 text-sm text-secondary">
                    {item.romanization}
                  </p>
                  <p class="meaning mt-1 text-base-content/80">
                    {Enum.join(Item.meanings(item), ", ")}
                  </p>
                  <p :if={item.metadata["context"]} class="mt-1 text-sm text-base-content/60">
                    {item.metadata["context"]}
                  </p>
                  <p :if={item.metadata["literal"]} class="mt-1 text-sm text-base-content/60">
                    Literally: <em>{item.metadata["literal"]}</em>
                  </p>
                  <p :if={item.notes} class="mt-1 text-sm text-base-content/60">{item.notes}</p>
                  <p
                    :for={variant <- Map.get(@variants, item.id, [])}
                    id={"#{dom_id}-variant-#{variant.id}"}
                    class="mt-2 flex flex-wrap items-center gap-2 text-sm text-base-content/60"
                  >
                    Also said
                    <.korean class="font-medium text-base-content/80">{variant.korean}</.korean>
                    <.politeness_badge
                      :if={variant.metadata["politeness"]}
                      level={variant.metadata["politeness"]}
                    />
                  </p>
                </div>
              </li>
            </ul>
          </section>
        </div>
      <% else %>
        <p id="no-phrases" class="mt-8 text-base-content/60">No phrases yet.</p>
      <% end %>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    {:ok,
     socket
     |> assign(:page_title, "Phrases")
     |> assign(:decks, Content.list_decks_with_items(:phrases))
     |> assign(:levels, [nil | Item.politeness_levels()])
     |> assign(:enrolled, SRS.enrolled_deck_ids(scope))
     |> assign(:tts_rate, SRS.get_settings(scope).tts_rate)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    decks = socket.assigns.decks
    # An unknown situation falls back to the first one rather than failing:
    # these links get shared and bookmarked.
    deck = Enum.find(decks, &(&1.slug == params["situation"])) || List.first(decks)
    politeness = Enum.find(Item.politeness_levels(), &(&1 == params["politeness"]))
    items = if deck, do: deck.items, else: []

    {:noreply,
     socket
     |> assign(:deck, deck)
     |> assign(:politeness, politeness)
     |> assign(:page_title, if(deck, do: "#{deck.title} · Phrases", else: "Phrases"))
     |> assign(:variants, variants(items))
     |> stream(:phrases, filter_politeness(items, politeness), reset: true)}
  end

  @impl true
  def handle_event("toggle_enroll", _params, %{assigns: %{current_scope: nil}} = socket) do
    {:noreply, push_navigate(socket, to: ~p"/users/log-in")}
  end

  def handle_event("toggle_enroll", %{"id" => id}, socket) do
    %{current_scope: scope, decks: decks, enrolled: enrolled} = socket.assigns

    case Enum.find(decks, &(to_string(&1.id) == id)) do
      nil ->
        {:noreply, socket}

      deck ->
        enrolled =
          if MapSet.member?(enrolled, deck.id) do
            {:ok, _} = SRS.unenroll_deck(scope, deck)
            MapSet.delete(enrolled, deck.id)
          else
            {:ok, _} = SRS.enroll_deck(scope, deck)
            MapSet.put(enrolled, deck.id)
          end

        {:noreply, assign(socket, :enrolled, enrolled)}
    end
  end

  defp phrases_path(deck, nil), do: ~p"/phrases?#{[situation: deck.slug]}"

  defp phrases_path(deck, politeness),
    do: ~p"/phrases?#{[situation: deck.slug, politeness: politeness]}"

  defp filter_politeness(items, nil), do: items

  defp filter_politeness(items, politeness),
    do: Enum.filter(items, &(&1.metadata["politeness"] == politeness))

  # `variant_of` points one way, from a form to the one it varies; each
  # phrase lists the other in both directions.
  defp variants(items) do
    by_key = Map.new(items, &{&1.source_key, &1})

    Enum.reduce(items, %{}, fn item, acc ->
      case by_key[item.metadata["variant_of"]] do
        nil ->
          acc

        other ->
          acc
          |> Map.update(item.id, [other], &(&1 ++ [other]))
          |> Map.update(other.id, [item], &(&1 ++ [item]))
      end
    end)
  end

  defp level_label(nil), do: "All"
  defp level_label("formal"), do: "Formal"
  defp level_label("polite"), do: "Polite"
  defp level_label("casual"), do: "Casual"
end
