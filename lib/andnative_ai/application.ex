defmodule AndnativeAi.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        AndnativeAiWeb.Telemetry,
        AndnativeAi.Repo,
        {DNSCluster, query: Application.get_env(:andnative_ai, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: AndnativeAi.PubSub},
        {Oban, Application.fetch_env!(:andnative_ai, Oban)}
      ] ++ service_children() ++ [AndnativeAiWeb.Endpoint]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: AndnativeAi.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AndnativeAiWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp service_children do
    case System.get_env("SERVICE_ROLE") do
      "slack-listener" -> [AndnativeAi.Slack.SocketModeListener]
      _role -> []
    end
  end
end
