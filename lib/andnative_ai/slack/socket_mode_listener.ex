defmodule AndnativeAi.Slack.SocketModeListener do
  use GenServer

  require Logger

  alias AndnativeAi.Memory
  alias AndnativeAi.Slack.{Client, SocketModeConnection}

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    state = %{
      app_token: Keyword.get(opts, :app_token, System.get_env("SLACK_APP_TOKEN", "")),
      bot_token: Keyword.get(opts, :bot_token, System.get_env("SLACK_BOT_TOKEN", "")),
      bot_user_id: Keyword.get(opts, :bot_user_id, System.get_env("SLACK_BOT_USER_ID", "")),
      history_limit: Keyword.get(opts, :history_limit, slack_history_limit()),
      client: Keyword.get(opts, :client, Client),
      connection: nil
    }

    if configured?(state) do
      send(self(), :connect)
    else
      Logger.warning("Slack Socket Mode listener disabled; set SLACK_APP_TOKEN.")
    end

    {:ok, state}
  end

  @impl true
  def handle_info(:connect, state) do
    tenant = Memory.ensure_demo_tenant!()

    case state.client.open_socket(state.app_token) do
      {:ok, url} ->
        opts = [
          client: state.client,
          bot_token: state.bot_token,
          bot_user_id: state.bot_user_id,
          team_id: System.get_env("SLACK_TEAM_ID", ""),
          history_limit: state.history_limit
        ]

        {:ok, connection} =
          SocketModeConnection.start_link(url, %{fallback_tenant_id: tenant.id, opts: opts})

        {:noreply, %{state | connection: connection}}

      {:error, reason} ->
        Logger.error("Slack Socket Mode connection failed: #{inspect(reason)}")
        Process.send_after(self(), :connect, 30_000)
        {:noreply, state}
    end
  end

  defp configured?(state) do
    valid_secret?(state.app_token)
  end

  defp valid_secret?(value), do: value != "" and not String.contains?(value, "replace-me")

  defp slack_history_limit do
    System.get_env("SLACK_HISTORY_LIMIT", "50") |> String.to_integer()
  end
end
