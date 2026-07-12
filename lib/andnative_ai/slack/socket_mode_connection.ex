defmodule AndnativeAi.Slack.SocketModeConnection do
  use WebSockex

  require Logger

  alias AndnativeAi.Slack.{Ingestion, Installations}

  def start_link(url, state) do
    WebSockex.start_link(url, __MODULE__, state)
  end

  @impl true
  def handle_frame({:text, payload}, state) do
    case Jason.decode(payload) do
      {:ok, %{"envelope_id" => envelope_id} = envelope} ->
        # Ack immediately: Slack resends envelopes not acked within ~3s,
        # and a model-backed answer takes longer than that — processing
        # inline caused duplicate replies. Retries are skipped outright as
        # a second guard.
        cond do
          retry?(envelope) ->
            :ok

          state[:sync_processing] ->
            handle_envelope(envelope, state)

          true ->
            Task.start(fn -> handle_envelope(envelope, state) end)
        end

        {:reply, {:text, Jason.encode!(%{envelope_id: envelope_id})}, state}

      {:ok, %{"type" => "hello"}} ->
        Logger.info("Slack Socket Mode connected.")
        {:ok, state}

      {:ok, %{"type" => "disconnect"} = frame} ->
        # Slack refreshes socket connections periodically; the URL from
        # apps.connections.open is single-use, so close and let the
        # listener open a fresh one.
        Logger.info("Slack requested socket refresh (#{frame["reason"]}); reconnecting.")
        {:close, state}

      other ->
        Logger.warning("Ignoring unrecognized Slack Socket Mode frame: #{inspect(other)}")
        {:ok, state}
    end
  end

  def handle_frame(_frame, state), do: {:ok, state}

  @impl true
  def handle_disconnect(connection_status, state) do
    # Never reconnect here: the socket URL has expired. Stopping lets the
    # listener request a fresh URL via apps.connections.open.
    Logger.warning(
      "Slack Socket Mode disconnected: #{inspect(Map.get(connection_status, :reason))}"
    )

    {:ok, state}
  end

  @doc "Slack marks redelivered envelopes; we ack them but never reprocess."
  def retry?(%{"retry_attempt" => attempt}) when is_integer(attempt) and attempt > 0, do: true

  def retry?(%{"payload" => %{"retry_attempt" => attempt}})
      when is_integer(attempt) and attempt > 0,
      do: true

  def retry?(_envelope), do: false

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
