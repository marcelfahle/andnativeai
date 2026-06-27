defmodule AndnativeAi.Slack.SocketModeConnection do
  use WebSockex

  require Logger

  alias AndnativeAi.Slack.Ingestion

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

  defp handle_envelope(%{"payload" => %{"event" => event}}, state) do
    Ingestion.handle_event(state.tenant_id, event, state.opts)
  end

  defp handle_envelope(_envelope, _state), do: {:ignored, :unsupported_envelope}
end
