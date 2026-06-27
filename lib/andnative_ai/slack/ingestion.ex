defmodule AndnativeAi.Slack.Ingestion do
  alias AndnativeAi.Memory
  alias AndnativeAi.Memory.Service
  alias AndnativeAi.Slack.Client

  def handle_event(tenant_id, %{"type" => "member_joined_channel"} = event, opts) do
    bot_user_id = Keyword.get(opts, :bot_user_id)

    if event["user"] == bot_user_id do
      backfill_channel(tenant_id, event, opts)
    else
      {:ignored, :not_bot_join}
    end
  end

  def handle_event(tenant_id, %{"type" => type} = event, opts)
      when type in ["member_left_channel", "member_kicked_channel"] do
    bot_user_id = Keyword.get(opts, :bot_user_id)

    if event["user"] == bot_user_id do
      delete_channel(tenant_id, event["channel"])
    else
      {:ignored, :not_bot_leave}
    end
  end

  def handle_event(tenant_id, %{"type" => "message", "channel" => channel_id} = event, opts) do
    cond do
      Map.has_key?(event, "subtype") ->
        {:ignored, :message_subtype}

      joined_channel?(tenant_id, channel_id) ->
        ingest_messages(tenant_id, channel_id, [event], opts)

      true ->
        {:ignored, :unjoined_channel}
    end
  end

  def handle_event(_tenant_id, _event, _opts), do: {:ignored, :unsupported_event}

  def backfill_channel(tenant_id, event, opts) do
    channel_id = event["channel"]
    client = Keyword.get(opts, :client, Client)
    bot_token = Keyword.fetch!(opts, :bot_token)
    limit = Keyword.get(opts, :history_limit, 50)

    messages =
      case client.conversations_history(bot_token, channel_id, limit: limit) do
        {:ok, messages} -> messages
        {:error, _reason} -> []
      end

    ingest_messages(tenant_id, channel_id, messages, opts)
  end

  def ingest_messages(tenant_id, channel_id, messages, opts) do
    chunks =
      messages
      |> Enum.reject(&(Map.get(&1, "text", "") == ""))
      |> Enum.map(&message_chunk(channel_id, &1, opts))

    Service.ingest(
      tenant_id,
      %{
        source_type: "slack_channel",
        source_id: channel_id,
        name: channel_name(channel_id, opts),
        permalink_or_url: "slack://channel/#{channel_id}"
      },
      chunks,
      %{"slack_channel" => channel_id},
      "tenant",
      "default"
    )
  end

  def delete_channel(tenant_id, channel_id) do
    case Memory.get_source_by_external_id(tenant_id, "slack_channel", channel_id) do
      nil -> {:ignored, :unknown_channel}
      source -> Service.delete_source(tenant_id, source.id)
    end
  end

  def joined_channel?(tenant_id, channel_id) do
    case Memory.get_source_by_external_id(tenant_id, "slack_channel", channel_id) do
      nil -> false
      source -> is_nil(source.deleted_at)
    end
  end

  defp message_chunk(channel_id, message, opts) do
    ts = message["ts"] || message["event_ts"] || ""
    client = Keyword.get(opts, :client, Client)
    bot_token = Keyword.get(opts, :bot_token, "")
    {:ok, permalink} = client.permalink(bot_token, channel_id, ts)

    %{
      text: message["text"],
      channel_id: channel_id,
      provenance: %{
        "slack_channel" => channel_id,
        "slack_ts" => ts,
        "author" => message["user"],
        "permalink" => permalink
      }
    }
  end

  defp channel_name(channel_id, opts) do
    Keyword.get(opts, :channel_name) || "Slack #{channel_id}"
  end
end
