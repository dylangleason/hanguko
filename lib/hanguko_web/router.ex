defmodule HangukoWeb.Router do
  use HangukoWeb, :router

  import HangukoWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {HangukoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", HangukoWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  # scope "/api", HangukoWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:hanguko, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: HangukoWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", HangukoWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{HangukoWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email

      # Studying is per user, so these require logging in.
      live "/dashboard", DashboardLive, :index
      live "/study", StudyLive, :index
      live "/study/settings", StudySettingsLive, :edit
      live "/stats", StatsLive, :index
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", HangukoWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{HangukoWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new

      # Curriculum browsing is public; studying (enrolling) requires a user,
      # which the LiveViews check before acting.
      live "/hangeul", HangeulLive, :index
      live "/decks", DeckLive.Index, :index
      live "/decks/:slug", DeckLive.Show, :show
      live "/grammar", GrammarLive.Index, :index
      live "/grammar/:slug", GrammarLive.Show, :show
      live "/phrases", PhraseLive, :index
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
