defmodule HangukoWeb.GrammarLive.Index do
  use HangukoWeb, :live_view

  alias Hanguko.Content
  alias Hanguko.Content.GrammarPoint

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@page_title}
        <:subtitle>
          Each lesson explains one pattern and shows it in sentences. Mark a lesson as learned and
          its sentences join your flashcards.
        </:subtitle>
      </.header>

      <div :for={{level, points} <- @levels} class="mt-8">
        <h2
          id={"level-#{level}"}
          class="text-xs font-semibold tracking-wide text-base-content/50 uppercase"
        >
          Level {level}
        </h2>

        <ul class="mt-3 grid gap-3 sm:grid-cols-2">
          <li
            :for={point <- points}
            id={"grammar-#{point.id}"}
            class="group relative flex flex-col rounded-box border border-base-300 bg-base-100 p-5 transition hover:-translate-y-0.5 hover:shadow-md"
          >
            <div class="flex items-start justify-between gap-3">
              <.korean class="text-xl font-semibold">
                <.link
                  navigate={~p"/grammar/#{point.slug}"}
                  class="after:absolute after:inset-0 group-hover:text-primary"
                >
                  {point.title}
                </.link>
              </.korean>
              <span
                :if={GrammarPoint.learned?(point)}
                id={"learned-#{point.id}"}
                title="Learned"
                class="inline-flex shrink-0 items-center gap-1 rounded-full bg-success/15 px-2 py-0.5 text-xs font-semibold text-success"
              >
                <.icon name="hero-check" class="size-3.5" /> Learned
              </span>
            </div>
            <.korean class="mt-1 text-sm text-base-content/60">{point.pattern}</.korean>
            <p class="mt-3 text-sm text-base-content/70">{point.summary}</p>
          </li>
        </ul>
      </div>

      <p :if={@levels == []} id="grammar-empty" class="mt-8 text-base-content/60">
        No grammar lessons yet.
      </p>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    levels =
      socket.assigns.current_scope
      |> Content.list_grammar_points()
      |> Enum.chunk_by(& &1.level)
      |> Enum.map(&{hd(&1).level, &1})

    {:ok, socket |> assign(:page_title, "Grammar") |> assign(:levels, levels)}
  end
end
