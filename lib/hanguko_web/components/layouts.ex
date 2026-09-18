defmodule HangukoWeb.Layouts do
  @moduledoc """
  The application layout and the main navigation.

  The bar puts the learner's own pages (Study, Cards, Progress) ahead of the
  curriculum, with everything about the account — settings, study settings,
  theme, log out — in one menu, so it stays readable as sections are added.
  Below 1024px it collapses to a menu button rather than squeezing.

  The current section is marked with `aria-current`. `HangukoWeb.Nav` keeps
  `@current_path` up to date, LiveViews pass it on as
  `<Layouts.app current_path={@current_path}>`, and `nav_section/1` maps a
  path to its section by its first segment, so inner pages (a lesson, study
  settings) mark their section too. Deck pages are the exception — `/decks`
  serves Hangeul, vocabulary and phrase decks alike — which is why `app/1`
  also takes a `section` attribute for a page to name its own.
  """
  use HangukoWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :current_path, :string,
    default: nil,
    doc: "the page's path, which marks its section in the nav (see `HangukoWeb.Nav`)"

  attr :section, :string,
    default: nil,
    doc: """
    the nav section to mark, for pages whose path doesn't say: deck pages
    serve every kind of deck, so they pass the deck's kind
    """

  slot :inner_block, required: true

  def app(assigns) do
    assigns = assign(assigns, :section, assigns.section || nav_section(assigns.current_path))

    ~H"""
    <header
      id="site-header"
      class="sticky top-0 z-30 border-b border-base-300 bg-base-100/85 backdrop-blur"
      phx-click-away={close_mobile_menu()}
      phx-window-keydown={close_mobile_menu()}
      phx-key="escape"
    >
      <nav class="mx-auto flex max-w-5xl items-center gap-3 px-4 py-2.5 sm:px-6" aria-label="Main">
        <.link navigate={~p"/"} class="group mr-3 flex shrink-0 items-baseline gap-1.5" id="brand">
          <span lang="ko" class="text-xl font-bold text-primary transition group-hover:opacity-80">
            한국어
          </span>
          <span class="text-sm font-semibold tracking-wide">Hanguko</span>
        </.link>

        <%!-- Desktop: the learner's own pages, then the curriculum --%>
        <div class="hidden min-w-0 flex-1 items-center gap-1 lg:flex">
          <%= for {group, index} <- Enum.with_index(nav_groups(@current_scope)) do %>
            <span :if={index > 0} class="mx-2 h-5 w-px bg-base-300" aria-hidden="true"></span>
            <.nav_link
              :for={{label, path, id} <- group}
              navigate={path}
              id={"nav-#{id}"}
              aria-current={@section == id && "page"}
            >
              {label}
            </.nav_link>
          <% end %>
        </div>

        <div class="hidden shrink-0 items-center gap-3 lg:flex">
          <%= if @current_scope do %>
            <.account_menu current_scope={@current_scope} />
          <% else %>
            <.theme_toggle />
            <div class="flex items-center gap-1 text-sm">
              <.link
                navigate={~p"/users/log-in"}
                id="nav-log-in"
                class="rounded-field px-2 py-1.5 text-base-content/70 transition hover:bg-base-200 hover:text-base-content"
              >
                Log in
              </.link>
              <.link
                navigate={~p"/users/register"}
                id="nav-register"
                class="rounded-field bg-primary px-3 py-1.5 font-medium text-primary-content transition hover:brightness-110"
              >
                Sign up
              </.link>
            </div>
          <% end %>
        </div>

        <%!-- Narrower screens: a menu button that opens the panel below --%>
        <button
          type="button"
          id="mobile-menu-button"
          class="group ml-auto inline-flex size-10 cursor-pointer items-center justify-center rounded-field text-base-content/70 transition hover:bg-base-200 hover:text-base-content lg:hidden"
          aria-label="Menu"
          aria-controls="mobile-menu"
          aria-expanded="false"
          phx-click={toggle_mobile_menu()}
        >
          <.icon name="hero-bars-3" class="size-6 group-aria-expanded:hidden" />
          <.icon name="hero-x-mark" class="hidden size-6 group-aria-expanded:inline-block" />
        </button>
      </nav>

      <div
        id="mobile-menu"
        class="hidden border-t border-base-300 lg:hidden"
        data-close={close_mobile_menu()}
      >
        <div class="mx-auto max-w-5xl px-4 py-3 sm:px-6">
          <%= for {group, index} <- Enum.with_index(nav_groups(@current_scope)) do %>
            <div :if={index > 0} class="my-2 border-t border-base-300"></div>
            <.mobile_link
              :for={{label, path, id} <- group}
              navigate={path}
              id={"mobile-nav-#{id}"}
              aria-current={@section == id && "page"}
            >
              {label}
            </.mobile_link>
          <% end %>

          <div class="my-3 border-t border-base-300"></div>

          <%= if @current_scope do %>
            <.mobile_link navigate={~p"/users/settings"} id="mobile-nav-settings">
              <.icon name="hero-user-circle" class="size-5 shrink-0" />
              <span class="truncate">{@current_scope.user.email}</span>
            </.mobile_link>
            <.mobile_link navigate={~p"/study/settings"} id="mobile-nav-study-settings">
              <.icon name="hero-adjustments-horizontal" class="size-5 shrink-0" /> Study settings
            </.mobile_link>
            <.mobile_link href={~p"/users/log-out"} method="delete" id="mobile-nav-log-out">
              <.icon name="hero-arrow-right-start-on-rectangle" class="size-5 shrink-0" /> Log out
            </.mobile_link>
          <% else %>
            <.mobile_link navigate={~p"/users/log-in"} id="mobile-nav-log-in">Log in</.mobile_link>
            <.link
              navigate={~p"/users/register"}
              id="mobile-nav-register"
              class="mt-2 block rounded-field bg-primary px-3 py-2.5 text-center font-medium text-primary-content transition hover:brightness-110"
            >
              Sign up
            </.link>
          <% end %>

          <div class="mt-3 flex items-center justify-between px-3 py-1.5">
            <span class="text-sm text-base-content/60">Theme</span>
            <.theme_toggle />
          </div>
        </div>
      </div>
    </header>

    <main class="px-4 py-8 sm:px-6 sm:py-12">
      <div class="mx-auto max-w-5xl">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  # The learner's own pages come first, set apart from the curriculum, which
  # anyone can browse.
  defp nav_groups(current_scope) do
    curriculum = [
      {"Hangeul", ~p"/hangeul", "hangeul"},
      {"Vocabulary", ~p"/decks?kind=vocab", "vocab"},
      {"Grammar", ~p"/grammar", "grammar"},
      {"Phrases", ~p"/phrases", "phrases"}
    ]

    learner = [
      {"Study", ~p"/dashboard", "study"},
      {"Cards", ~p"/cards", "cards"},
      {"Progress", ~p"/stats", "progress"}
    ]

    if current_scope, do: [learner, curriculum], else: [curriculum]
  end

  # The nav section a path belongs to, by its first segment, so a lesson or
  # study settings count as part of their section. `/decks` isn't here: it
  # serves every kind of deck, and deck pages pass `section` instead.
  defp nav_section(nil), do: nil

  defp nav_section(path) do
    case String.split(path, "/", trim: true) do
      ["dashboard" | _] -> "study"
      ["study" | _] -> "study"
      ["stats" | _] -> "progress"
      ["cards" | _] -> "cards"
      ["hangeul" | _] -> "hangeul"
      ["grammar" | _] -> "grammar"
      ["phrases" | _] -> "phrases"
      _ -> nil
    end
  end

  attr :navigate, :string, required: true
  attr :rest, :global
  slot :inner_block, required: true

  defp nav_link(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class="shrink-0 rounded-field px-3 py-1.5 text-sm font-medium text-base-content/70 transition hover:bg-base-200 hover:text-base-content aria-[current=page]:bg-base-200 aria-[current=page]:text-base-content"
      {@rest}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  attr :rest, :global, include: ~w(navigate href method)
  slot :inner_block, required: true

  defp mobile_link(assigns) do
    ~H"""
    <.link
      class="flex items-center gap-2 rounded-field px-3 py-2.5 font-medium text-base-content/80 transition hover:bg-base-200 hover:text-base-content aria-[current=page]:bg-base-200 aria-[current=page]:text-base-content"
      {@rest}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  attr :current_scope, :map, required: true

  # A disclosure rather than an ARIA menu: a button that shows a panel of
  # ordinary links, so Tab and Enter work without extra key handling.
  defp account_menu(assigns) do
    ~H"""
    <div
      class="relative"
      phx-click-away={close_account_menu()}
      phx-window-keydown={close_account_menu()}
      phx-key="escape"
    >
      <button
        type="button"
        id="account-menu-button"
        class="group flex cursor-pointer items-center gap-1 rounded-field px-2 py-1.5 text-base-content/70 transition hover:bg-base-200 hover:text-base-content aria-expanded:bg-base-200 aria-expanded:text-base-content"
        aria-label="Account"
        aria-controls="account-menu"
        aria-expanded="false"
        title={@current_scope.user.email}
        phx-click={toggle_account_menu()}
      >
        <.icon name="hero-user-circle" class="size-6" />
        <.icon
          name="hero-chevron-down-micro"
          class="size-4 transition group-aria-expanded:rotate-180"
        />
      </button>

      <div
        id="account-menu"
        class="absolute right-0 mt-2 hidden w-64 rounded-box border border-base-300 bg-base-100 p-2 text-sm shadow-lg"
        data-close={close_account_menu()}
      >
        <p class="truncate px-3 pt-1.5 pb-2 text-xs text-base-content/60" id="account-email">
          Logged in as <span class="font-medium text-base-content">{@current_scope.user.email}</span>
        </p>
        <.menu_link navigate={~p"/users/settings"} id="nav-settings">
          <.icon name="hero-user-circle" class="size-5 shrink-0" /> Account settings
        </.menu_link>
        <.menu_link navigate={~p"/study/settings"} id="nav-study-settings">
          <.icon name="hero-adjustments-horizontal" class="size-5 shrink-0" /> Study settings
        </.menu_link>

        <div class="my-2 border-t border-base-300"></div>

        <div class="flex items-center justify-between px-3 py-1.5">
          <span class="text-base-content/70">Theme</span>
          <.theme_toggle />
        </div>

        <div class="my-2 border-t border-base-300"></div>

        <.menu_link href={~p"/users/log-out"} method="delete" id="nav-log-out">
          <.icon name="hero-arrow-right-start-on-rectangle" class="size-5 shrink-0" /> Log out
        </.menu_link>
      </div>
    </div>
    """
  end

  attr :rest, :global, include: ~w(navigate href method)
  slot :inner_block, required: true

  defp menu_link(assigns) do
    ~H"""
    <.link
      class="flex items-center gap-2 rounded-field px-3 py-2 text-base-content/80 transition hover:bg-base-200 hover:text-base-content"
      {@rest}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  # Both menus also close when a live navigation starts (see the
  # `phx:page-loading-start` listener in app.js, which runs `data-close`).
  defp toggle_mobile_menu do
    JS.toggle_class("hidden", to: "#mobile-menu")
    |> JS.toggle_attribute({"aria-expanded", "true", "false"}, to: "#mobile-menu-button")
  end

  defp close_mobile_menu do
    JS.add_class("hidden", to: "#mobile-menu")
    |> JS.set_attribute({"aria-expanded", "false"}, to: "#mobile-menu-button")
  end

  defp toggle_account_menu do
    JS.toggle_class("hidden", to: "#account-menu")
    |> JS.toggle_attribute({"aria-expanded", "true", "false"}, to: "#account-menu-button")
  end

  defp close_account_menu do
    JS.add_class("hidden", to: "#account-menu")
    |> JS.set_attribute({"aria-expanded", "false"}, to: "#account-menu-button")
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
