defmodule HangukoWeb.DeckLive.Components do
  @moduledoc """
  Components shared by the deck pages.
  """
  use HangukoWeb, :html

  alias Hanguko.Content.Deck

  @doc """
  Adds or removes a deck from the user's studies (sends `toggle_enroll`).
  Anonymous visitors get a link to log in instead.
  """
  attr :id, :string, required: true
  attr :deck, Deck, required: true
  attr :enrolled, :boolean, required: true
  attr :current_scope, :any, required: true

  def enroll_button(assigns) do
    ~H"""
    <%= if @current_scope do %>
      <button
        id={@id}
        type="button"
        phx-click="toggle_enroll"
        phx-value-id={@deck.id}
        aria-pressed={to_string(@enrolled)}
        title={if(@enrolled, do: "Click to stop studying this deck")}
        class={[
          "group relative z-10 inline-flex shrink-0 cursor-pointer items-center gap-1.5 rounded-field px-3 py-1.5 text-sm font-medium transition active:scale-[0.97]",
          "phx-click-loading:opacity-60",
          if(@enrolled,
            do: "bg-success/15 text-success hover:bg-error/10 hover:text-error",
            else: "bg-primary text-primary-content shadow-sm hover:brightness-110"
          )
        ]}
      >
        <%= if @enrolled do %>
          <.icon name="hero-check" class="size-4 group-hover:hidden" />
          <.icon name="hero-x-mark" class="hidden size-4 group-hover:inline-block" />
          <span class="group-hover:hidden">Studying</span>
          <span class="hidden group-hover:inline">Remove</span>
        <% else %>
          <.icon name="hero-plus" class="size-4" /> Study
        <% end %>
      </button>
    <% else %>
      <.link
        id={@id}
        navigate={~p"/users/log-in"}
        class="relative z-10 inline-flex shrink-0 items-center gap-1.5 rounded-field border border-base-300 px-3 py-1.5 text-sm font-medium text-base-content/70 transition hover:border-base-content/30"
      >
        <.icon name="hero-lock-closed" class="size-4" /> Log in to study
      </.link>
    <% end %>
    """
  end
end
