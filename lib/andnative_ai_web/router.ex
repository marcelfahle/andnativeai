defmodule AndnativeAiWeb.Router do
  use AndnativeAiWeb, :router

  import AndnativeAiWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AndnativeAiWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  ## Public routes (no authentication required)

  scope "/", AndnativeAiWeb do
    pipe_through :browser

    get "/", PageController, :home

    # Slack must be able to reach the OAuth callback without an admin session.
    get "/slack/oauth/callback", SlackOAuthController, :callback

    post "/login", UserSessionController, :create
    delete "/logout", UserSessionController, :delete

    live_session :redirect_if_user_is_authenticated,
      on_mount: [{AndnativeAiWeb.UserAuth, :redirect_if_user_is_authenticated}] do
      live "/login", UserLoginLive
    end

    live_session :public_account,
      on_mount: [{AndnativeAiWeb.UserAuth, :mount_current_user}] do
      live "/users/reset-password", UserForgotPasswordLive
      live "/users/reset-password/:token", UserResetPasswordLive
      live "/users/invite/:token", UserAcceptInvitationLive
    end
  end

  ## Authenticated admin routes

  scope "/", AndnativeAiWeb do
    pipe_through [:browser, :require_authenticated_user]

    # Starting the Slack install flow requires a logged-in admin.
    get "/slack/install", SlackOAuthController, :install

    live_session :require_authenticated_user,
      on_mount: [{AndnativeAiWeb.UserAuth, :require_authenticated}] do
      live "/admin/control-plane", Admin.ControlPlaneLive
      live "/admin/memory", Admin.MemoryMapLive
      live "/admin/agents", Admin.AgentsLive
      live "/admin/sources", Admin.DocumentsLive
      live "/admin/documents", Admin.DocumentsLive
      live "/admin/slack", Admin.SlackLive
      live "/admin/runtime", Admin.RuntimeLive
      live "/admin/skills", Admin.SkillsLive
      live "/admin/prospects", Admin.ProspectPlansLive
      live "/admin/prospects/:id", Admin.ProspectPlanLive

      live "/users/settings", UserSettingsLive
      live "/admin/users", Admin.UsersLive
      live "/admin/users/invite", Admin.UserInviteLive
    end
  end

  scope "/api", AndnativeAiWeb do
    pipe_through :api

    post "/memory/search", Api.MemoryController, :search
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:andnative_ai, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: AndnativeAiWeb.Telemetry
    end
  end
end
