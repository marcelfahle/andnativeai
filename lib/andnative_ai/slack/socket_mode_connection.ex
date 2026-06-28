defmodule AndnativeAi.Slack.SocketModeConnection do
  use WebSockex

  require Logger

  alias AndnativeAi.Slack.{Ingestion, Installations}

  def start_link(url, state) do
    WebSockex.start_link(url, __MODULE__, state)
  end

  @impl true
  def handle_frame({:text, payload}, state) do
    with {:ok, envelope} <- Jason.decode(payload),
         %{"envelope_id" => envelope_id} <- envelope do
      handle_envelope(envelope, state)
      {:reply, {:text, Jason.encode!(%{envelope_id: envelope_id})}, state}
    else
      error ->
        Logger.warning("Ignoring malformed Slack Socket Mode frame: #{inspect(error)}")
        {:ok, state}
    end
  end

  def handle_frame(_frame, state), do: {:ok, state}

  @impl true
  def handle_disconnect(_connection_status, state), do: {:reconnect, state}

  defp handle_envelope(%{"payload" => %{"event" => event} = payload}, state) do
    case Installations.resolve_payload(payload, state.fallback_tenant_id, state.opts) do
      {:ok, tenant_id, opts} ->
        Ingestion.handle_event(tenant_id, event, opts)

      {:error, reason} ->
        Logger.warning("Ignoring Slack event without matching installation: #{inspect(reason)}")
        {:ignored, reason}
    end
  end

  defp handle_envelope(_envelope, _state), do: {:ignored, :unsupported_envelope}
end
