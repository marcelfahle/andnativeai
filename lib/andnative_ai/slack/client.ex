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

  def post_message(bot_token, channel_id, text, thread_ts) do
    post_message(bot_token, channel_id, text, thread_ts, [])
  end

  # `username`/`icon_url` overrides need the chat:write.customize scope;
  # without it Slack ignores them rather than failing the post.
  def post_message(bot_token, channel_id, text, thread_ts, opts) do
    payload =
      %{
        channel: channel_id,
        text: text,
        thread_ts: thread_ts
      }
      |> maybe_put(:username, opts[:username])
      |> maybe_put(:icon_url, opts[:icon_url])

    post("/chat.postMessage", bot_token, payload)
  end

  defp maybe_put(payload, _key, nil), do: payload
  defp maybe_put(payload, key, value), do: Map.put(payload, key, value)

  @doc """
  Uploads a file into a channel thread using the external upload flow
  (`files.upload` is retired): get an upload URL, POST the bytes, complete
  the upload with the share target.
  """
  def upload_file(bot_token, channel_id, thread_ts, filename, content) do
    with {:ok, %{"upload_url" => upload_url, "file_id" => file_id}} <-
           get("/files.getUploadURLExternal", bot_token, %{
             filename: filename,
             length: byte_size(content)
           }),
         {:ok, _response} <- put_bytes(upload_url, content),
         {:ok, body} <-
           post(
             "/files.completeUploadExternal",
             bot_token,
             %{
               files: [%{id: file_id, title: filename}],
               channel_id: channel_id
             }
             |> maybe_put_thread_ts(thread_ts)
           ) do
      {:ok, body}
    end
  end

  defp put_bytes(upload_url, content) do
    case Req.request(method: :post, url: upload_url, body: content) do
      {:ok, %{status: status}} when status in 200..299 -> {:ok, :uploaded}
      {:ok, %{status: status}} -> {:error, {:upload_failed, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_put_thread_ts(body, thread_ts) when thread_ts in [nil, ""], do: body
  defp maybe_put_thread_ts(body, thread_ts), do: Map.put(body, :thread_ts, thread_ts)

  def oauth_v2_access(client_id, client_secret, code, redirect_uri) do
    params =
      %{
        client_id: client_id,
        client_secret: client_secret,
        code: code
      }
      |> maybe_put_redirect_uri(redirect_uri)

    request(:post, "/oauth.v2.access", nil, form: params)
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
    [method: method, url: @api <> path]
    |> maybe_put_bearer_auth(token)
    |> Keyword.merge(opts)
    |> Req.request()
    |> case do
      {:ok, %{body: %{"ok" => true} = body}} -> {:ok, body}
      {:ok, %{body: body}} -> {:error, body}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_put_redirect_uri(params, ""), do: params
  defp maybe_put_redirect_uri(params, nil), do: params

  defp maybe_put_redirect_uri(params, redirect_uri),
    do: Map.put(params, :redirect_uri, redirect_uri)

  defp maybe_put_bearer_auth(opts, token) when token in [nil, ""], do: opts
  defp maybe_put_bearer_auth(opts, token), do: Keyword.put(opts, :auth, {:bearer, token})
end
