defmodule AndnativeAi.Research.Gemini do
  @moduledoc """
  Google Gemini Deep Research adapter via the Interactions API
  (`deep-research-preview-04-2026`): background interaction, then poll by
  id. Second-choice provider — best native markdown+citations, but the
  agent snapshots still carry `-preview-`, so expect version churn.
  """

  @behaviour AndnativeAi.Research.Provider

  @api "https://generativelanguage.googleapis.com/v1beta"
  @agent "deep-research-preview-04-2026"

  @impl true
  def submit(query, _opts \\ []) do
    body = %{
      agent: @agent,
      input: query,
      background: true
    }

    case request(:post, "/interactions", json: body) do
      {:ok, %{"id" => id}} -> {:ok, id}
      {:ok, %{"name" => name}} -> {:ok, name}
      {:ok, body} -> {:error, {:unexpected_response, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def poll(interaction_id) do
    case request(:get, "/interactions/#{interaction_id}", []) do
      {:ok, %{"status" => status} = body} -> handle_status(status, interaction_id, body)
      {:ok, %{"state" => status} = body} -> handle_status(status, interaction_id, body)
      {:ok, body} -> {:error, {:unexpected_response, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle_status(status, interaction_id, body) do
    cond do
      status in ["in_progress", "IN_PROGRESS", "queued", "QUEUED", "running", "RUNNING"] ->
        {:pending, interaction_id}

      status in ["completed", "COMPLETED", "succeeded", "SUCCEEDED"] ->
        {:done,
         %{
           markdown: extract_text(body),
           citations: extract_citations(body),
           provider: "gemini/#{@agent}",
           cost_cents: nil
         }}

      true ->
        {:error, {:research_failed, status, body["error"]}}
    end
  end

  defp extract_text(body) do
    outputs = body["outputs"] || body["output"] || []

    outputs
    |> List.wrap()
    |> Enum.map(fn
      %{"text" => text} when is_binary(text) -> text
      %{"content" => content} when is_binary(content) -> content
      _other -> ""
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  defp extract_citations(body) do
    body
    |> Map.get("citations", [])
    |> List.wrap()
    |> Enum.map(fn
      %{"url" => url} -> url
      url when is_binary(url) -> url
      _other -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp request(method, path, opts) do
    case System.get_env("GEMINI_API_KEY", "") do
      "" -> {:error, :research_provider_not_configured}
      api_key -> do_request(method, path, opts, api_key)
    end
  end

  defp do_request(method, path, opts, api_key) do
    [
      method: method,
      url: @api <> path,
      headers: [{"x-goog-api-key", api_key}],
      receive_timeout: 60_000
    ]
    |> Keyword.merge(opts)
    |> Req.request()
    |> case do
      {:ok, %{status: status, body: body}} when status in 200..299 -> {:ok, body}
      {:ok, %{status: status, body: body}} -> {:error, {:http_error, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end
end
