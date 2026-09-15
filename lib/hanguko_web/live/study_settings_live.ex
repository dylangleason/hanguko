defmodule HangukoWeb.StudySettingsLive do
  @moduledoc """
  Study preferences: daily limits, target retention, time zone and display.
  """
  use HangukoWeb, :live_view

  alias Hanguko.SRS

  @retention_options [
    {"80% · fewer reviews", 0.8},
    {"85%", 0.85},
    {"90% · recommended", 0.9},
    {"95% · more reviews", 0.95}
  ]

  @speech_rates [{"Slow", 0.7}, {"Relaxed", 0.8}, {"Natural", 0.9}, {"Fast", 1.1}]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <div class="mx-auto max-w-xl">
        <.link
          navigate={~p"/dashboard"}
          class="inline-flex items-center gap-1 text-sm text-base-content/60 transition hover:text-base-content"
        >
          <.icon name="hero-arrow-left" class="size-4" /> Today
        </.link>

        <.header>
          Study settings
          <:subtitle>How much to study each day, and how cards are shown.</:subtitle>
        </.header>

        <.form
          for={@form}
          id="study-settings-form"
          phx-change="validate"
          phx-submit="save"
          class="mt-6 space-y-8"
        >
          <fieldset class="space-y-2">
            <legend class="mb-2 font-semibold">Daily limits</legend>
            <.input
              field={@form[:daily_new_limit]}
              type="number"
              label="New cards per day"
              min="0"
              max="100"
            />
            <.input
              field={@form[:daily_review_limit]}
              type="number"
              label="Maximum reviews per day"
              min="0"
              max="9999"
            />
            <p class="text-sm text-base-content/60">
              Each new word takes two cards: recognizing it, then (from the next day) saying it in Korean.
            </p>
          </fieldset>

          <fieldset class="space-y-2">
            <legend class="mb-2 font-semibold">Scheduling</legend>
            <.input
              field={@form[:desired_retention]}
              type="select"
              label="How much to remember"
              options={@retention_options}
            />
            <p class="text-sm text-base-content/60">
              Reviews are timed so you remember this share of cards. Higher means more reviews.
            </p>
            <.input
              field={@form[:timezone]}
              type="text"
              label="Time zone"
              placeholder="Detected from your browser"
              autocomplete="off"
            />
            <p class="text-sm text-base-content/60">
              A name like Asia/Seoul or America/New_York. Leave it empty to use your browser's.
            </p>
            <.input
              field={@form[:day_rollover_hour]}
              type="select"
              label="A new study day starts at"
              options={for h <- 0..23, do: {String.pad_leading("#{h}", 2, "0") <> ":00", h}}
            />
          </fieldset>

          <fieldset class="space-y-2">
            <legend class="mb-2 font-semibold">Display</legend>
            <.input
              field={@form[:show_romanization]}
              type="checkbox"
              label="Show romanization on answers"
            />
            <.input
              field={@form[:typed_answers]}
              type="checkbox"
              label="Type the Korean on recall cards"
            />
            <p class="text-sm text-base-content/60">
              Instead of just thinking of the answer, type it and see which letters you got wrong.
            </p>
            <.input
              field={@form[:tts_rate]}
              type="select"
              label="Speech speed"
              options={@speech_rates}
            />
          </fieldset>

          <button
            type="submit"
            id="save-study-settings"
            phx-disable-with="Saving..."
            class="w-full cursor-pointer rounded-field bg-primary py-2.5 font-semibold text-primary-content transition hover:brightness-110"
          >
            Save settings
          </button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    settings = SRS.get_settings(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(:page_title, "Study settings")
     |> assign(:settings, settings)
     |> assign(:retention_options, @retention_options)
     |> assign(:speech_rates, @speech_rates)
     |> assign(:form, to_form(SRS.change_settings(settings)))}
  end

  @impl true
  def handle_event("validate", %{"settings" => params}, socket) do
    changeset = SRS.change_settings(socket.assigns.settings, params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"settings" => params}, socket) do
    case SRS.update_settings(socket.assigns.current_scope, params) do
      {:ok, settings} ->
        {:noreply,
         socket
         |> assign(:settings, settings)
         |> assign(:form, to_form(SRS.change_settings(settings)))
         |> put_flash(:info, "Study settings saved.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end
end
