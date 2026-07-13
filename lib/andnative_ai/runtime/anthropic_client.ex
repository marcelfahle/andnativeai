defmodule AndnativeAi.Runtime.AnthropicClient do
  @moduledoc """
  Anthropic Messages API client with the same request/response contract
  as `OpenAIClient`: the caller supplies `api_key` in the request map
  (call sites own env reads and missing-key short-circuits), and the
  result is `{:ok, text} | {:error, reason}`.
  """

  @api "https://api.anthropic.com/v1/messages"
  @api_version "2023-06-01"

  def response(request) do
    body = %{
      model: request.model,
      system: request.instructions,
      messages: [%{role: "user", content: request.input}],
      max_tokens: Map.get(request, :max_output_tokens, 280)
    }

    [
      method: :post,
      url: @api,
      headers: [
        {"x-api-key", request.api_key},
        {"anthropic-version", @api_version}
      ],
      json: body,
      receive_timeout: 20_000
    ]
    |> Req.request()
    |> case do
      {:ok, %{status: 200, body: %{"content" => content}}} when is_list(content) ->
        extract_text(content)

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_anthropic_response, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_text(content) do
    text =
      content
      |> Enum.filter(&(Map.get(&1, "type") == "text"))
      |> Enum.map(&Map.get(&1, "text", ""))
      |> Enum.join("")
      |> String.trim()

    if text == "", do: {:error, :missing_output_text}, else: {:ok, text}
  end
end
