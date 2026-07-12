defmodule AndnativeAi.Research.Perplexity do
  @moduledoc """
  Perplexity `sonar-deep-research` adapter using the async chat-completions
  endpoint: submit returns a request id, poll fetches it until the report is
  ready. Chosen as the default provider: stable API, simplest call shape,
  cheapest per query (~$0.30-1.30).
  """

  @behaviour AndnativeAi.Research.Provider

  @api "https://api.perplexity.ai"

  @impl true
  def submit(query, opts \\ []) do
    body = %{
      request: %{
        model: "sonar-deep-research",
        messages: [
          %{
            role: "system",
            content:
              "Produce a thorough, well-structured markdown research report with clear sections. Cite sources."
          },
          %{role: "user", content: query}
        ],
        reasoning_effort: Keyword.get(opts, :reasoning_effort, "medium")
      }
    }

    case request(:post, "/async/chat/completions", json: body) do
      {:ok, %{"id" => id}} -> {:ok, id}
      {:ok, body} -> {:error, {:unexpected_response, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def poll(request_id) do
    case request(:get, "/async/chat/completions/#{request_id}", []) do
      {:ok, %{"status" => status} = body} ->
        handle_status(status, request_id, body)

      {:ok, body} ->
        {:error, {:unexpected_response, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_status("COMPLETED", _request_id, body) do
    response = body["response"] || body

    content =
      get_in(response, ["choices", Access.at(0), "message", "content"]) || ""

    citations = extract_citations(response)

    {:done,
     %{
       markdown: strip_think(content),
       citations: citations,
       provider: "perplexity/sonar-deep-research",
       cost_cents: extract_cost_cents(response)
     }}
  end

  defp handle_status(status, request_id, _body)
       when status in ["CREATED", "PROCESSING", "IN_PROGRESS"],
       do: {:pending, request_id}

  defp handle_status(status, _request_id, body),
    do: {:error, {:research_failed, status, body["error_message"]}}

  defp extract_citations(response) do
    cond do
      is_list(response["citations"]) and response["citations"] != [] ->
        response["citations"]

      is_list(response["search_results"]) ->
        response["search_results"] |> Enum.map(& &1["url"]) |> Enum.reject(&is_nil/1)

      true ->
        []
    end
  end

  # Deep research responses may include the model's reasoning inside
  # <think> tags; the dossier should only carry the final report.
  defp strip_think(content) do
    content
    |> String.replace(~r/<think>.*?<\/think>/s, "")
    |> String.trim()
  end

  defp extract_cost_cents(response) do
    case get_in(response, ["usage", "cost", "total_cost"]) do
      cost when is_number(cost) -> round(cost * 100)
      _missing -> nil
    end
  end

  defp request(method, path, opts) do
    case System.get_env("PERPLEXITY_API_KEY", "") do
      "" -> {:error, :research_provider_not_configured}
      api_key -> do_request(method, path, opts, api_key)
    end
  end

  defp do_request(method, path, opts, api_key) do
    [method: method, url: @api <> path, auth: {:bearer, api_key}, receive_timeout: 60_000]
    |> Keyword.merge(opts)
    |> Req.request()
    |> case do
      {:ok, %{status: status, body: body}} when status in 200..299 -> {:ok, body}
      {:ok, %{status: status, body: body}} -> {:error, {:http_error, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end
end
