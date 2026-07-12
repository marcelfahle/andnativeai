defmodule AndnativeAi.Slack.Ingestion do
  alias AndnativeAi.Memory
  alias AndnativeAi.Memory.Service
  alias AndnativeAi.Memory.Source
  alias AndnativeAi.Runtime.Responder
  alias AndnativeAi.Slack.Client
  alias AndnativeAi.Slack.Distiller
  alias AndnativeAi.Slack.MessageText

  def handle_event(tenant_id, %{"type" => "app_mention"} = event, opts) do
    Responder.respond_to_slack(tenant_id, event, opts)
  end

  def handle_event(tenant_id, %{"type" => "member_joined_channel"} = event, opts) do
    bot_user_id = Keyword.get(opts, :bot_user_id)

    if event["user"] == bot_user_id do
      replace_channel_memory(tenant_id, event["channel"])
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

  def handle_event(
        tenant_id,
        %{"type" => "message", "subtype" => subtype, "channel" => channel_id} = event,
        opts
      )
      when subtype in ["message_changed", "message_deleted"] do
    if joined_channel?(tenant_id, channel_id) do
      replace_channel_memory(tenant_id, channel_id)
      backfill_channel(tenant_id, event, opts)
    else
      {:ignored, :unjoined_channel}
    end
  end

  def handle_event(tenant_id, %{"type" => "message", "channel" => channel_id} = event, opts) do
    source = Memory.get_source_by_external_id(tenant_id, "slack_channel", channel_id)
    app_message? = MessageText.app_message?(event)

    cond do
      bot_authored?(event, opts) ->
        {:ignored, :bot_authored_message}

      app_message? and not joined_channel?(source) ->
        {:ignored, :unjoined_channel}

      app_message? and not Source.ingest_bot_messages?(source) ->
        {:ignored, :bot_ingestion_disabled}

      app_message? ->
        ingest_messages(tenant_id, channel_id, [event], opts)

      Map.has_key?(event, "subtype") ->
        {:ignored, :message_subtype}

      mentions_bot?(event, opts) ->
        {:ignored, :bot_mention_memory}

      joined_channel?(source) ->
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
    source = Memory.get_source_by_external_id(tenant_id, "slack_channel", channel_id)
    allow_app_messages? = Source.ingest_bot_messages?(source)

    chunks =
      messages
      |> Enum.reject(&bot_authored?(&1, opts))
      |> Enum.reject(&mentions_bot?(&1, opts))
      |> Enum.reject(&(MessageText.app_message?(&1) and not allow_app_messages?))
      |> Enum.map(&MessageText.normalize/1)
      |> then(&Distiller.distill(channel_id, &1, opts))

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
    tenant_id
    |> Memory.get_source_by_external_id("slack_channel", channel_id)
    |> joined_channel?()
  end

  def joined_channel?(nil), do: false
  def joined_channel?(%Source{deleted_at: deleted_at}), do: is_nil(deleted_at)

  defp replace_channel_memory(_tenant_id, nil), do: :ok

  defp replace_channel_memory(tenant_id, channel_id) do
    case Memory.get_source_by_external_id(tenant_id, "slack_channel", channel_id) do
      nil -> :ok
      source -> Service.delete_source(tenant_id, source.id)
    end
  end

  defp bot_authored?(event, opts) do
    MessageText.self_authored?(event, Keyword.get(opts, :bot_user_id))
  end

  defp mentions_bot?(%{"text" => text}, opts) when is_binary(text) do
    bot_user_id = Keyword.get(opts, :bot_user_id)
    bot_user_id not in [nil, ""] and String.contains?(text, "<@#{bot_user_id}>")
  end

  defp mentions_bot?(_event, _opts), do: false

  defp channel_name(channel_id, opts) do
    Keyword.get(opts, :channel_name) || "Slack #{channel_id}"
  end
end
