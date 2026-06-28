defmodule AndnativeAiWeb.Router do
  use AndnativeAiWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AndnativeAiWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", AndnativeAiWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/slack/install", SlackOAuthController, :install
    get "/slack/oauth/callback", SlackOAuthController, :callback
    live "/admin/agents", Admin.AgentsLive
    live "/admin/sources", Admin.DocumentsLive
    live "/admin/documents", Admin.DocumentsLive
    live "/admin/slack", Admin.SlackLive
    live "/admin/runtime", Admin.RuntimeLive
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
