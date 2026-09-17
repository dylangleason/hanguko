defmodule HangukoWeb.GrammarLive.Show do
  use HangukoWeb, :live_view

  alias Hanguko.{Content, Korean, SRS}
  alias Hanguko.Content.{GrammarPoint, Item}
  alias HangukoWeb.Markdown
  alias HangukoWeb.Live.PerUserAction

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <div class="mx-auto max-w-2xl">
        <.link
          navigate={~p"/grammar"}
          id="back-to-grammar"
          class="inline-flex items-center gap-1 text-sm text-base-content/60 transition hover:text-base-content"
        >
          <.icon name="hero-arrow-left" class="size-4" /> All grammar
        </.link>

        <header class="mt-4 flex flex-wrap items-start justify-between gap-4">
          <div>
            <.korean class="text-3xl font-bold">{@point.title}</.korean>
            <.korean class="mt-1 block text-base-content/60">{@point.pattern}</.korean>
            <p :if={@point.summary} class="mt-2 text-base-content/70">{@point.summary}</p>
          </div>

          <button
            type="button"
            id="toggle-learned"
            phx-click={if(@learned, do: "unmark_learned", else: "mark_learned")}
            class={[
              "inline-flex cursor-pointer items-center gap-2 rounded-field px-4 py-2 text-sm font-semibold transition",
              if(@learned,
                do: "bg-success/15 text-success hover:bg-success/25",
                else: "bg-primary text-primary-content hover:brightness-110"
              )
            ]}
          >
            <.icon name={if(@learned, do: "hero-check", else: "hero-plus")} class="size-4" />
            {if(@learned, do: "Learned", else: "Mark as learned")}
          </button>
        </header>

        <p
          :if={@learned and @deck}
          id="learned-note"
          class="mt-4 flex flex-wrap items-center gap-2 rounded-box border border-success/30 bg-success/10 px-4 py-3 text-sm"
        >
          These sentences are in your flashcards.
          <.link
            navigate={~p"/study?deck=#{@deck.slug}"}
            id="study-grammar"
            class="font-semibold text-success hover:underline"
          >
            Study them now
          </.link>
        </p>

        <section
          id="explanation"
          class="mt-6 space-y-3 text-base-content/80 [&_em]:italic [&_li]:mt-1 [&_strong]:font-semibold [&_strong]:text-base-content [&_ul]:list-disc [&_ul]:pl-5"
        >
          {Markdown.to_html(@point.explanation)}
        </section>

        <section :if={@point.formation != []} class="mt-8">
          <h2 class="text-sm font-semibold tracking-wide text-base-content/50 uppercase">
            How it's formed
          </h2>

          <div class="mt-3 overflow-x-auto">
            <table id="formation" class="w-full text-sm">
              <thead class="text-left text-xs tracking-wide text-base-content/50 uppercase">
                <tr>
                  <th class="py-2 pr-4 font-semibold">When</th>
                  <th class="py-2 pr-4 font-semibold">Form</th>
                  <th class="py-2 font-semibold">Example</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={{row, i} <- Enum.with_index(@point.formation)}
                  id={"formation-#{i}"}
                  class="border-t border-base-300"
                >
                  <td class="py-2.5 pr-4 text-base-content/70">{row["when"]}</td>
                  <td class="py-2.5 pr-4">
                    <.korean class="font-semibold">{row["form"]}</.korean>
                  </td>
                  <td class="py-2.5">
                    <.korean class="text-base-content/70">{row["example"]}</.korean>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <form
            :if={@batchim_rows != []}
            id="try-it"
            phx-change="try"
            class="mt-5 rounded-box border border-base-300 bg-base-200/40 p-4"
          >
            <label for="try-word" class="text-sm font-semibold">Try it</label>
            <p class="mt-1 text-sm text-base-content/60">
              Type a Korean word and see which form it takes.
            </p>
            <input
              type="text"
              id="try-word"
              name="word"
              value={@try_word}
              autocomplete="off"
              placeholder="학생"
              lang="ko"
              class="mt-3 w-full rounded-field border border-base-300 bg-base-100 px-3 py-2 font-korean focus:border-primary focus:outline-none"
            />

            <p
              :if={@try_result == :not_korean}
              id="try-hint"
              class="mt-3 text-sm text-base-content/60"
            >
              That doesn't end in a Hangul syllable yet.
            </p>

            <p
              :if={match?({:ok, _, _}, @try_result)}
              id="try-answer"
              class="mt-3 flex flex-wrap items-baseline gap-2 text-sm"
            >
              <span class="text-base-content/60">{elem(@try_result, 1)["when"]} →</span>
              <.korean class="text-lg font-semibold">{elem(@try_result, 2)}</.korean>
              <.speak_button id="try-speak" text={elem(@try_result, 2)} rate={@tts_rate} />
            </p>
          </form>
        </section>

        <section class="mt-8">
          <h2 class="text-sm font-semibold tracking-wide text-base-content/50 uppercase">
            Examples
          </h2>

          <ul id="examples" class="mt-3 divide-y divide-base-300 border-y border-base-300">
            <li
              :for={item <- @point.items}
              id={"example-#{item.id}"}
              class="flex items-start gap-3 py-4"
            >
              <.speak_button
                id={"example-speak-#{item.id}"}
                text={item.korean}
                rate={@tts_rate}
                class="mt-0.5"
              />
              <div>
                <.korean class="text-lg">
                  <%= case Item.cloze_parts(item) do %>
                    <% {before, target, rest} -> %>
                      {before}<mark class="rounded bg-primary/15 px-0.5 text-primary">{target}</mark>{rest}
                    <% nil -> %>
                      {item.korean}
                  <% end %>
                </.korean>
                <p class="mt-1 text-sm text-base-content/70">{item.meaning}</p>
                <p :if={item.notes} class="mt-1 text-sm text-base-content/50">{item.notes}</p>
              </div>
            </li>
          </ul>
        </section>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    scope = socket.assigns.current_scope
    point = Content.get_grammar_point_by_slug!(scope, slug)

    {:ok,
     socket
     |> assign(:page_title, point.title)
     |> assign(:point, point)
     |> assign(:deck, point.deck)
     |> assign(:learned, GrammarPoint.learned?(point))
     |> assign(:batchim_rows, Enum.filter(point.formation, &is_boolean(&1["batchim"])))
     |> assign(:tts_rate, SRS.get_settings(scope).tts_rate)
     |> assign_try("")}
  end

  @impl true
  def handle_event("try", %{"word" => word}, socket) do
    {:noreply, assign_try(socket, word)}
  end

  def handle_event(event, _params, %{assigns: %{current_scope: nil}} = socket)
      when event in ~w(mark_learned unmark_learned) do
    PerUserAction.require_scope(socket)
  end

  def handle_event("mark_learned", _params, socket) do
    %{current_scope: scope, point: point, deck: deck} = socket.assigns
    {:ok, _} = Content.mark_grammar_learned(scope, point)
    # Its sentences can only be studied from a deck the learner is studying.
    if deck, do: {:ok, _} = SRS.enroll_deck(scope, deck)

    {:noreply, assign(socket, :learned, true)}
  end

  def handle_event("unmark_learned", _params, socket) do
    {:ok, _} = Content.unmark_grammar_learned(socket.assigns.current_scope, socket.assigns.point)
    {:noreply, assign(socket, :learned, false)}
  end

  defp assign_try(socket, word) do
    socket |> assign(:try_word, word) |> assign(:try_result, try_form(socket.assigns, word))
  end

  # Which formation row a word takes, and what it looks like joined up.
  defp try_form(%{batchim_rows: []}, _word), do: nil

  defp try_form(%{batchim_rows: rows}, word) do
    word = String.trim(word)

    cond do
      word == "" ->
        nil

      not Korean.syllable?(String.last(word) || "") ->
        :not_korean

      true ->
        row = Enum.find(rows, &(&1["batchim"] == Korean.has_batchim?(word)))
        row && {:ok, row, join(word, row["form"])}
    end
  end

  # "학생" + "이에요" -> "학생이에요", and "가" + "-ㄹ 거예요" -> "갈 거예요":
  # an ending that starts with a final consonant is written into the last
  # syllable rather than added after it.
  defp join(word, form) do
    ending = String.trim_leading(form, "-")

    with <<first::utf8, rest::binary>> <- ending,
         jamo = <<first::utf8>>,
         true <- jamo in Korean.finals(),
         {initial, medial, nil} <- Korean.decompose(String.last(word)),
         {:ok, syllable} <- Korean.compose(initial, medial, jamo) do
      String.slice(word, 0..-2//1) <> syllable <> rest
    else
      _ -> word <> ending
    end
  end
end
