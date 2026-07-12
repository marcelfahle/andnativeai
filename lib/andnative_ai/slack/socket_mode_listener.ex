defmodule AndnativeAi.Slack.SocketModeListener do
  use GenServer

  require Logger

  alias AndnativeAi.Memory
  alias AndnativeAi.Slack.Client

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    # The socket process is linked; trap exits so an expired or dropped
    # connection triggers a fresh apps.connections.open instead of
    # crash-looping the listener through the supervisor.
    Process.flag(:trap_exit, true)

    state = %{
      app_token: Keyword.get(opts, :app_token, System.get_env("SLACK_APP_TOKEN", "")),
      bot_token: Keyword.get(opts, :bot_token, System.get_env("SLACK_BOT_TOKEN", "")),
      bot_user_id: Keyword.get(opts, :bot_user_id, System.get_env("SLACK_BOT_USER_ID", "")),
      history_limit: Keyword.get(opts, :history_limit, slack_history_limit()),
      client: Keyword.get(opts, :client, Client),
      connection_module:
        Keyword.get(opts, :connection_module, AndnativeAi.Slack.SocketModeConnection),
      reconnect_delay_ms: Keyword.get(opts, :reconnect_delay_ms, 5_000),
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
          state.connection_module.start_link(url, %{fallback_tenant_id: tenant.id, opts: opts})

        {:noreply, %{state | connection: connection}}

      {:error, reason} ->
        Logger.error("Slack Socket Mode connection failed: #{inspect(reason)}")
        Process.send_after(self(), :connect, 30_000)
        {:noreply, state}
    end
  end

  # The socket process ended (Slack refresh, network drop, expired URL).
  # Open a fresh single-use URL after a short delay.
  def handle_info({:EXIT, pid, reason}, %{connection: pid} = state) do
    Logger.warning(
      "Slack Socket Mode connection ended (#{inspect(reason)}); reconnecting in #{state.reconnect_delay_ms}ms."
    )

    Process.send_after(self(), :connect, state.reconnect_delay_ms)
    {:noreply, %{state | connection: nil}}
  end

  def handle_info({:EXIT, _other_pid, _reason}, state), do: {:noreply, state}

  defp configured?(state) do
    valid_secret?(state.app_token)
  end

  defp valid_secret?(value), do: value != "" and not String.contains?(value, "replace-me")

  defp slack_history_limit do
    System.get_env("SLACK_HISTORY_LIMIT", "50") |> String.to_integer()
  end
end
