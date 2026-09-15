defmodule HangukoWeb.DeckLive.Show do
  use HangukoWeb, :live_view

  import HangukoWeb.DeckLive.Components

  alias Hanguko.{Content, SRS}
  alias Hanguko.Content.Item

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_path={@current_path}
      section={to_string(@deck.kind)}
    >
      <.link
        navigate={~p"/decks?kind=#{@deck.kind}"}
        id="back-to-decks"
        class="inline-flex items-center gap-1 text-sm text-base-content/60 transition hover:text-base-content"
      >
        <.icon name="hero-arrow-left" class="size-4" /> {deck_kind_label(@deck.kind)}
      </.link>

      <header class="mt-4 flex flex-wrap items-start justify-between gap-4">
        <div class="min-w-0">
          <h1 class="text-3xl font-bold tracking-tight">
            {@deck.title}
            <.korean :if={@deck.title_ko} class="ml-1 text-2xl font-medium text-base-content/50">
              {@deck.title_ko}
            </.korean>
          </h1>
          <p class="mt-2 max-w-2xl text-base-content/70">{@deck.description}</p>
          <p class="mt-2 text-sm text-base-content/50">
            Level {@deck.level} · {@item_count} items
          </p>
        </div>
        <div class="flex items-center gap-2">
          <.link
            :if={@enrolled}
            navigate={~p"/study?deck=#{@deck.slug}"}
            id="study-deck"
            class="inline-flex items-center gap-1.5 rounded-field bg-primary px-3 py-1.5 text-sm font-medium text-primary-content shadow-sm transition hover:brightness-110"
          >
            Study now <.icon name="hero-arrow-right" class="size-4" />
          </.link>
          <.enroll_button
            id="enroll"
            deck={@deck}
            enrolled={@enrolled}
            current_scope={@current_scope}
          />
        </div>
      </header>

      <div class="mt-6 flex flex-wrap gap-2">
        <.reveal_toggle id="toggle-romanization" target="#items" class_name="hide-romanization">
          Hide romanization
        </.reveal_toggle>
        <.reveal_toggle id="toggle-meaning" target="#items" class_name="hide-meaning">
          Hide meanings
        </.reveal_toggle>
      </div>

      <ol
        id="items"
        phx-update="stream"
        class="mt-4 divide-y divide-base-300 overflow-hidden rounded-box border border-base-300 bg-base-100"
      >
        <li
          :for={{dom_id, item} <- @streams.items}
          id={dom_id}
          class="flex items-start gap-3 px-4 py-3.5 transition hover:bg-base-200/50 sm:gap-4 sm:px-5"
        >
          <.speak_button id={"#{dom_id}-speak"} text={Item.speech_text(item)} class="mt-0.5" />
          <div class="min-w-0 flex-1">
            <div class="flex flex-wrap items-baseline gap-x-3 gap-y-1">
              <.korean class="text-2xl font-medium">{item.korean}</.korean>
              <span :if={item.romanization} class="romanization text-sm text-secondary">
                {item.romanization}
              </span>
              <.politeness_badge
                :if={item.metadata["politeness"]}
                level={item.metadata["politeness"]}
              />
            </div>
            <p class="meaning mt-0.5 text-base-content/80">
              {Enum.join(Item.meanings(item), ", ")}
              <span :if={item.part_of_speech} class="ml-1 text-xs text-base-content/40">
                {item.part_of_speech}
              </span>
            </p>
            <p :if={item.metadata["literal"]} class="mt-1 text-sm text-base-content/60">
              Literally: <em>{item.metadata["literal"]}</em>
            </p>
            <p :if={item.metadata["example_word"]} class="mt-1 text-sm text-base-content/60">
              <.korean class="text-base-content/80">{item.metadata["name"]}</.korean>
              · as in
              <.korean class="font-medium text-base-content/80">
                {item.metadata["example_word"]}
              </.korean>
              ({item.metadata["example_meaning"]})
            </p>
            <p :if={item.hint} class="mt-1 text-sm text-base-content/60">{item.hint}</p>
            <p :if={item.notes} class="mt-1 text-sm text-base-content/60">{item.notes}</p>
          </div>
        </li>
      </ol>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    deck = Content.get_deck_by_slug!(slug)

    {:ok,
     socket
     |> assign(:page_title, deck.title)
     |> assign(:deck, %{deck | items: []})
     |> assign(:item_count, length(deck.items))
     |> assign(:enrolled, SRS.enrolled?(socket.assigns.current_scope, deck))
     |> stream(:items, deck.items)}
  end

  @impl true
  def handle_event("toggle_enroll", _params, socket) do
    %{current_scope: scope, deck: deck, enrolled: enrolled} = socket.assigns

    cond do
      is_nil(scope) ->
        {:noreply, push_navigate(socket, to: ~p"/users/log-in")}

      enrolled ->
        {:ok, _} = SRS.unenroll_deck(scope, deck)
        {:noreply, assign(socket, :enrolled, false)}

      true ->
        {:ok, _} = SRS.enroll_deck(scope, deck)
        {:noreply, assign(socket, :enrolled, true)}
    end
  end
end
