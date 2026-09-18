defmodule HangukoWeb.HangeulLive do
  @moduledoc """
  Learn to read Hangeul: letter charts, an interactive syllable builder and
  a breakdown of any word into its letters.
  """
  use HangukoWeb, :live_view

  alias Hanguko.{Content, Korean}

  # How final consonants (batchim) are pronounced: only seven sounds exist.
  @final_sounds [
    {"k", ~w(ㄱ ㄲ ㅋ)},
    {"n", ~w(ㄴ)},
    {"t", ~w(ㄷ ㅅ ㅆ ㅈ ㅊ ㅌ ㅎ)},
    {"l", ~w(ㄹ)},
    {"m", ~w(ㅁ)},
    {"p", ~w(ㅂ ㅍ)},
    {"ng", ~w(ㅇ)}
  ]

  @max_analysis_length 30

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <.header>
        Hangeul
        <.korean class="ml-1 font-medium text-base-content/50">한글</.korean>
        <:subtitle>
          Korean is written with 40 letters (jamo) grouped into square syllable blocks. Each block
          starts with a consonant, has a vowel, and may end with a final consonant (batchim). Click a
          letter to put it in the syllable builder.
        </:subtitle>
      </.header>

      <div class="mt-8 grid items-start gap-8 lg:grid-cols-[minmax(0,1fr)_20rem]">
        <aside
          id="builder"
          class="rounded-box border border-base-300 bg-base-100 p-4 sm:p-5 lg:sticky lg:top-20 lg:order-last"
        >
          <div class="flex items-center justify-between">
            <h2 class="font-semibold">Syllable builder</h2>
            <button
              type="button"
              id="builder-random"
              phx-click="random"
              class="inline-flex cursor-pointer items-center gap-1 rounded-field px-2 py-1 text-sm text-base-content/60 transition hover:bg-base-200 hover:text-base-content"
            >
              <.icon name="hero-arrow-path" class="size-4" /> Random
            </button>
          </div>

          <div id="builder-result" class="mt-4 flex flex-col items-center">
            <div class="flex items-center gap-2">
              <.korean id="builder-syllable" class="text-8xl leading-none font-medium">
                {@syllable}
              </.korean>
              <.speak_button id="builder-speak" text={@syllable} size="lg" />
            </div>
            <p class="mt-3 text-lg font-semibold text-secondary">{Korean.romanize(@syllable)}</p>
            <p lang="ko" class="mt-1 text-sm text-base-content/60">
              {@initial} + {@medial}{if(@final, do: " + #{@final}")} = {@syllable}
            </p>
          </div>

          <div class="mt-5 space-y-4">
            <.jamo_picker
              part="initial"
              label="First consonant"
              options={@initials}
              selected={@initial}
            />
            <.jamo_picker part="medial" label="Vowel" options={@medials} selected={@medial} />
            <.jamo_picker
              part="final"
              label="Final consonant"
              options={@finals}
              selected={@final}
              allow_none
            />
          </div>
        </aside>

        <div id="charts" class="space-y-10">
          <div class="flex flex-wrap gap-2">
            <.reveal_toggle id="toggle-romanization" target="#charts" class_name="hide-romanization">
              Hide sounds
            </.reveal_toggle>
          </div>

          <section :for={deck <- @decks} id={"chart-#{deck.slug}"}>
            <div class="flex flex-wrap items-baseline justify-between gap-2">
              <h2 class="text-xl font-semibold">
                {deck.title}
                <.korean class="ml-1 text-base font-medium text-base-content/50">
                  {deck.title_ko}
                </.korean>
              </h2>
              <.link
                navigate={~p"/decks/#{deck.slug}"}
                class="text-sm font-medium text-primary hover:underline"
              >
                Study these letters →
              </.link>
            </div>
            <p class="mt-1 max-w-2xl text-sm text-base-content/70">{deck.description}</p>
            <div class="mt-4 grid grid-cols-3 gap-2 sm:grid-cols-4 xl:grid-cols-5">
              <.jamo_tile
                :for={item <- deck.items}
                id={"jamo-#{item.id}"}
                item={item}
                event="pick"
                selected={item.korean in [@initial, @medial]}
              />
            </div>
          </section>

          <section id="final-sounds">
            <h2 class="text-xl font-semibold">
              Final consonants
              <.korean class="ml-1 text-base font-medium text-base-content/50">받침</.korean>
            </h2>
            <p class="mt-1 max-w-2xl text-sm text-base-content/70">
              At the end of a syllable, every consonant collapses into one of just seven sounds. When
              the next syllable starts with the silent ㅇ, the final consonant moves over and is
              pronounced fully instead: 음악 is said 으막 (eumak).
            </p>
            <div class="mt-4 grid grid-cols-2 gap-2 sm:grid-cols-4">
              <div
                :for={{sound, letters} <- @final_sounds}
                class="rounded-box border border-base-300 bg-base-100 px-4 py-3"
              >
                <p class="romanization text-lg font-semibold text-secondary">[{sound}]</p>
                <.korean class="text-xl">{Enum.join(letters, " ")}</.korean>
              </div>
            </div>
          </section>

          <section id="analyze">
            <h2 class="text-xl font-semibold">Take a word apart</h2>
            <p class="mt-1 text-sm text-base-content/70">
              Type or paste any Korean text to see the letters in each syllable.
            </p>
            <.form
              for={@analyze_form}
              id="analyze-form"
              phx-change="analyze"
              phx-submit="analyze"
              class="mt-3 max-w-sm"
            >
              <.input
                field={@analyze_form[:text]}
                type="text"
                lang="ko"
                autocomplete="off"
                placeholder="한국어"
              />
            </.form>
            <div id="analysis" class="mt-2 flex flex-wrap gap-2">
              <div
                :for={{part, index} <- Enum.with_index(@analysis)}
                id={"analysis-#{index}"}
                class="flex min-w-20 flex-col items-center rounded-box border border-base-300 bg-base-100 px-3 py-2"
              >
                <.korean class="text-3xl font-medium">{part.char}</.korean>
                <%= if part.jamo do %>
                  <.korean class="mt-1 text-sm tracking-widest text-base-content/60">
                    {part.jamo |> Tuple.to_list() |> Enum.reject(&is_nil/1) |> Enum.join(" ")}
                  </.korean>
                  <span class="romanization text-xs font-semibold text-secondary">{part.roman}</span>
                <% end %>
              </div>
            </div>
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :part, :string, required: true
  attr :label, :string, required: true
  attr :options, :list, required: true
  attr :selected, :string, default: nil
  attr :allow_none, :boolean, default: false

  defp jamo_picker(assigns) do
    ~H"""
    <fieldset id={"picker-#{@part}"}>
      <legend class="mb-1.5 text-xs font-semibold tracking-wide text-base-content/50 uppercase">
        {@label}
      </legend>
      <div class="grid grid-cols-7 gap-1">
        <button
          :if={@allow_none}
          type="button"
          phx-click="set"
          phx-value-part={@part}
          phx-value-jamo=""
          aria-label="No final consonant"
          aria-pressed={to_string(is_nil(@selected))}
          class={picker_class(is_nil(@selected))}
        >
          –
        </button>
        <button
          :for={jamo <- @options}
          type="button"
          phx-click="set"
          phx-value-part={@part}
          phx-value-jamo={jamo}
          lang="ko"
          aria-pressed={to_string(jamo == @selected)}
          class={picker_class(jamo == @selected)}
        >
          {jamo}
        </button>
      </div>
    </fieldset>
    """
  end

  defp picker_class(selected?) do
    [
      "aspect-square cursor-pointer rounded-field text-base transition active:scale-90",
      if(selected?,
        do: "bg-primary font-semibold text-primary-content shadow-sm",
        else: "bg-base-200 hover:bg-base-300"
      )
    ]
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Hangeul")
     |> assign(:decks, Content.list_decks_with_items(:hangeul))
     |> assign(:initials, Korean.initials())
     |> assign(:medials, Korean.medials())
     |> assign(:finals, Korean.finals())
     |> assign(:final_sounds, @final_sounds)
     |> assign_syllable("ㅎ", "ㅏ", "ㄴ")
     |> assign_analysis("한국어")}
  end

  @impl true
  def handle_event("pick", %{"jamo" => jamo}, socket) do
    %{initial: initial, medial: medial, final: final} = socket.assigns

    socket =
      cond do
        jamo in Korean.initials() -> assign_syllable(socket, jamo, medial, final)
        jamo in Korean.medials() -> assign_syllable(socket, initial, jamo, final)
        true -> socket
      end

    {:noreply, socket}
  end

  def handle_event("set", %{"part" => part} = params, socket) do
    %{initial: initial, medial: medial, final: final} = socket.assigns
    jamo = params["jamo"]

    socket =
      case part do
        "initial" -> assign_syllable(socket, jamo, medial, final)
        "medial" -> assign_syllable(socket, initial, jamo, final)
        "final" -> assign_syllable(socket, initial, medial, jamo)
        _ -> socket
      end

    {:noreply, socket}
  end

  def handle_event("random", _params, socket) do
    final = if :rand.uniform(2) == 1, do: nil, else: Enum.random(Korean.finals())

    {:noreply,
     assign_syllable(
       socket,
       Enum.random(Korean.initials()),
       Enum.random(Korean.medials()),
       final
     )}
  end

  def handle_event("analyze", %{"analyze" => %{"text" => text}}, socket) do
    {:noreply, assign_analysis(socket, text)}
  end

  # Invalid combinations (e.g. a letter that can't end a syllable) are ignored.
  defp assign_syllable(socket, initial, medial, final) do
    final = if final == "", do: nil, else: final

    case Korean.compose(initial, medial, final) do
      {:ok, syllable} ->
        assign(socket, initial: initial, medial: medial, final: final, syllable: syllable)

      :error ->
        socket
    end
  end

  defp assign_analysis(socket, text) do
    text = String.slice(text, 0, @max_analysis_length)

    analysis =
      for char <- String.graphemes(text), String.trim(char) != "" do
        %{char: char, jamo: Korean.decompose(char), roman: Korean.romanize(char)}
      end

    socket
    |> assign(:analyze_form, to_form(%{"text" => text}, as: :analyze))
    |> assign(:analysis, analysis)
  end
end
