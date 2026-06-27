defmodule AndnativeAi.Slack.Distiller do
  alias AndnativeAi.Slack.Client

  @noise ~w(ok okay thanks thank thx +1 yep yes no ack acknowledged)
  @durable_markers ~w(
    approved approval approvals choose chosen commit committed commitment decided decision due fact
    citation citations follow launch need owner preference prefer requires should todo will
  )

  def distill(channel_id, messages, opts \\ []) do
    messages
    |> Enum.reject(&noise?/1)
    |> group_messages(Keyword.get(opts, :window_seconds, 900))
    |> Enum.flat_map(&summarize_group(channel_id, &1, opts))
  end

  def noise?(%{"text" => text}) when is_binary(text) do
    normalized =
      text
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9+]+/u, " ")
      |> String.trim()

    normalized == "" or normalized in @noise or String.length(normalized) <= 2
  end

  def noise?(_message), do: true

  defp group_messages(messages, window_seconds) do
    messages
    |> Enum.sort_by(&timestamp(&1))
    |> Enum.group_by(&thread_key(&1, window_seconds))
    |> Map.values()
  end

  defp thread_key(%{"thread_ts" => thread_ts}, _window_seconds) when is_binary(thread_ts),
    do: {:thread, thread_ts}

  defp thread_key(message, window_seconds) do
    bucket = floor(timestamp(message) / window_seconds)
    {:window, bucket}
  end

  defp summarize_group(_channel_id, [], _opts), do: []

  defp summarize_group(channel_id, messages, opts) do
    durable_messages = Enum.filter(messages, &durable?/1)

    if durable_messages == [] do
      []
    else
      first = List.first(durable_messages)
      client = Keyword.get(opts, :client, Client)
      bot_token = Keyword.get(opts, :bot_token, "")

      {:ok, permalink} =
        client.permalink(bot_token, channel_id, first["ts"] || first["event_ts"] || "")

      [
        %{
          text: summary_text(channel_id, durable_messages),
          channel_id: channel_id,
          provenance: %{
            "slack_channel" => channel_id,
            "slack_thread_ts" => first["thread_ts"] || first["ts"],
            "slack_ts" => first["ts"] || first["event_ts"],
            "authors" => authors(durable_messages),
            "message_count" => length(messages),
            "permalink" => permalink
          }
        }
      ]
    end
  end

  defp durable?(%{"text" => text}) do
    tokens =
      text
      |> String.downcase()
      |> String.split(~r/[^a-z0-9]+/u, trim: true)

    Enum.any?(tokens, &(&1 in @durable_markers)) or
      String.contains?(String.downcase(text), "we decided")
  end

  defp durable?(_message), do: false

  defp summary_text(channel_id, messages) do
    facts =
      messages
      |> Enum.map(&clean_text(&1["text"]))
      |> Enum.uniq()
      |> Enum.join(" ")

    "Slack memory from #{channel_id}: #{facts}"
  end

  defp clean_text(text) do
    text
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  defp authors(messages) do
    messages
    |> Enum.map(& &1["user"])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp timestamp(message) do
    message
    |> Map.get("ts", Map.get(message, "event_ts", "0"))
    |> parse_slack_ts()
  end

  defp parse_slack_ts(ts) when is_binary(ts) do
    ts
    |> String.split(".")
    |> List.first()
    |> Integer.parse()
    |> case do
      {value, _rest} -> value
      :error -> 0
    end
  end

  defp parse_slack_ts(_ts), do: 0
end
