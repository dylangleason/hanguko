defmodule HangukoWeb.KoreanComponents do
  @moduledoc """
  UI building blocks for displaying Korean study content.
  """
  use Phoenix.Component

  import HangukoWeb.CoreComponents, only: [icon: 1]

  alias Hanguko.Content.Item
  alias Phoenix.LiveView.JS

  @doc """
  Marks its content as Korean, which selects the Korean font stack and
  word-based line breaking (see `:lang(ko)` in app.css).
  """
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def korean(assigns) do
    ~H"""
    <span lang="ko" class={@class} {@rest}>{render_slot(@inner_block)}</span>
    """
  end

  @doc """
  A button that pronounces `text` (see the `Speak` hook in
  `assets/js/hooks/speak.js`). When `audio` is given, that file is played
  instead of synthesized speech.
  """
  attr :id, :string, required: true
  attr :text, :string, required: true
  attr :audio, :string, default: nil
  attr :rate, :float, default: nil
  attr :size, :string, default: "md", values: ~w(sm md lg)
  attr :class, :any, default: nil

  def speak_button(assigns) do
    ~H"""
    <button
      type="button"
      id={@id}
      phx-hook="Speak"
      data-text={@text}
      data-audio={@audio}
      data-rate={@rate}
      aria-label={"Listen to #{@text}"}
      title="Listen"
      class={[
        "group inline-flex shrink-0 cursor-pointer items-center justify-center rounded-full",
        "text-base-content/50 transition hover:bg-primary/10 hover:text-primary active:scale-90",
        "data-speaking:bg-primary/10 data-speaking:text-primary",
        @size == "sm" && "size-7",
        @size == "md" && "size-9",
        @size == "lg" && "size-12",
        @class
      ]}
    >
      <.icon
        name="hero-speaker-wave"
        class={[
          "group-data-speaking:animate-pulse",
          if(@size == "lg", do: "size-6", else: "size-5")
        ]}
      />
    </button>
    """
  end

  @doc """
  A Hangeul letter tile: the letter, its name, sound and an example word.
  Clicking the tile sends `event` with the letter as `jamo`.
  """
  attr :id, :string, required: true
  attr :item, Item, required: true
  attr :event, :string, default: nil
  attr :selected, :boolean, default: false

  def jamo_tile(assigns) do
    ~H"""
    <div id={@id} class="relative">
      <button
        type="button"
        phx-click={@event}
        phx-value-jamo={@item.korean}
        disabled={is_nil(@event)}
        aria-pressed={to_string(@selected)}
        class={[
          "flex w-full flex-col items-center rounded-box border px-2 pt-4 pb-3 text-center transition",
          "enabled:cursor-pointer enabled:hover:-translate-y-0.5 enabled:hover:shadow-md",
          if(@selected,
            do: "border-primary bg-primary/10 shadow-md",
            else: "border-base-300 bg-base-100 enabled:hover:border-primary/50"
          )
        ]}
      >
        <.korean class="text-5xl leading-none font-medium">{@item.korean}</.korean>
        <span class="romanization mt-2 text-sm font-semibold text-secondary">
          {@item.romanization}
        </span>
        <.korean class="mt-1 text-xs text-base-content/60">{@item.metadata["name"]}</.korean>
        <span :if={@item.metadata["example_word"]} class="mt-2 text-xs text-base-content/70">
          <.korean class="font-medium text-base-content">{@item.metadata["example_word"]}</.korean>
          · {@item.metadata["example_meaning"]}
        </span>
      </button>
      <.speak_button
        id={"#{@id}-speak"}
        text={Item.speech_text(@item)}
        size="sm"
        class="absolute top-1 right-1"
      />
    </div>
    """
  end

  @doc """
  A toggle button for self-testing: toggles `class_name` (`hide-romanization`
  or `hide-meaning`, see app.css) on the `target` container, blurring those
  values until hovered.
  """
  attr :id, :string, required: true
  attr :target, :string, required: true
  attr :class_name, :string, required: true, values: ~w(hide-romanization hide-meaning)
  slot :inner_block, required: true

  def reveal_toggle(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      aria-pressed="false"
      phx-click={
        JS.toggle_class(@class_name, to: @target)
        |> JS.toggle_attribute({"aria-pressed", "true", "false"})
      }
      class={[
        "inline-flex cursor-pointer items-center gap-1.5 rounded-field border border-base-300 bg-base-100",
        "px-3 py-1.5 text-sm text-base-content/70 transition hover:border-base-content/30",
        "aria-pressed:border-secondary/40 aria-pressed:bg-secondary/10 aria-pressed:text-secondary"
      ]}
    >
      <.icon name="hero-eye-slash" class="size-4" /> {render_slot(@inner_block)}
    </button>
    """
  end

  @doc "A badge naming a speech level: formal (합쇼체), polite (해요체) or casual (반말)."
  attr :level, :string, required: true

  def politeness_badge(assigns) do
    ~H"""
    <span
      :if={politeness_label(@level)}
      class={[
        "inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium whitespace-nowrap",
        @level == "formal" && "bg-secondary/10 text-secondary",
        @level == "polite" && "bg-success/15 text-success",
        @level == "casual" && "bg-warning/15 text-warning"
      ]}
      title={politeness_description(@level)}
    >
      {politeness_label(@level)}
      <.korean class="opacity-75">{politeness_ko(@level)}</.korean>
    </span>
    """
  end

  defp politeness_label("formal"), do: "Formal"
  defp politeness_label("polite"), do: "Polite"
  defp politeness_label("casual"), do: "Casual"
  defp politeness_label(_), do: nil

  defp politeness_ko("formal"), do: "합쇼체"
  defp politeness_ko("polite"), do: "해요체"
  defp politeness_ko("casual"), do: "반말"

  defp politeness_description("formal"),
    do: "Formal and deferential: announcements, business, first meetings with elders."

  defp politeness_description("polite"),
    do: "Polite everyday speech: safe with strangers, colleagues and acquaintances."

  defp politeness_description("casual"),
    do: "Casual speech: close friends, younger siblings and children only."

  @doc "A human-readable label for a deck kind."
  def deck_kind_label(:hangeul), do: "Hangeul"
  def deck_kind_label(:vocab), do: "Vocabulary"
  def deck_kind_label(:phrases), do: "Phrases"
  def deck_kind_label(:sentences), do: "Sentences"
end
