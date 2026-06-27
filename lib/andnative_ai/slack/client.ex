defmodule AndnativeAi.Slack.Client do
  @api "https://slack.com/api"

  def open_socket(app_token) do
    case post("/apps.connections.open", app_token, %{}) do
      {:ok, %{"url" => url}} -> {:ok, url}
      {:ok, body} -> {:error, body}
      {:error, reason} -> {:error, reason}
    end
  end

  def conversations_history(bot_token, channel_id, opts \\ []) do
    params = %{
      channel: channel_id,
      limit: Keyword.get(opts, :limit, 50)
    }

    case get("/conversations.history", bot_token, params) do
      {:ok, %{"messages" => messages}} -> {:ok, messages}
      {:ok, body} -> {:error, body}
      {:error, reason} -> {:error, reason}
    end
  end

  def permalink(bot_token, channel_id, message_ts) do
    params = %{channel: channel_id, message_ts: message_ts}

    case get("/chat.getPermalink", bot_token, params) do
      {:ok, %{"permalink" => permalink}} -> {:ok, permalink}
      {:ok, _body} -> {:ok, fallback_permalink(channel_id, message_ts)}
      {:error, _reason} -> {:ok, fallback_permalink(channel_id, message_ts)}
    end
  end

  def fallback_permalink(channel_id, message_ts),
    do: "slack://channel/#{channel_id}/#{message_ts}"

  defp get(path, token, params) do
    request(:get, path, token, params: params)
  end

  defp post(path, token, body) do
    request(:post, path, token, json: body)
  end

  defp request(method, path, token, opts) do
    [method: method, url: @api <> path, auth: {:bearer, token}]
    |> Keyword.merge(opts)
    |> Req.request()
    |> case do
      {:ok, %{body: %{"ok" => true} = body}} -> {:ok, body}
      {:ok, %{body: body}} -> {:error, body}
      {:error, reason} -> {:error, reason}
    end
  end
end
