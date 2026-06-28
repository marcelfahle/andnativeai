defmodule AndnativeAi.Runtime.OpenAIClient do
  @api "https://api.openai.com/v1/responses"

  def response(request) do
    body = %{
      model: request.model,
      instructions: request.instructions,
      input: request.input,
      max_output_tokens: Map.get(request, :max_output_tokens, 280)
    }

    [
      method: :post,
      url: @api,
      auth: {:bearer, request.api_key},
      json: body,
      receive_timeout: 20_000
    ]
    |> Req.request()
    |> case do
      {:ok, %{body: %{"output_text" => text}}} when is_binary(text) and text != "" ->
        {:ok, String.trim(text)}

      {:ok, %{body: body}} ->
        extract_output_text(body)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_output_text(%{"output" => output}) when is_list(output) do
    text =
      output
      |> Enum.flat_map(&Map.get(&1, "content", []))
      |> Enum.filter(&(Map.get(&1, "type") == "output_text"))
      |> Enum.map(&Map.get(&1, "text", ""))
      |> Enum.join("")
      |> String.trim()

    if text == "", do: {:error, :missing_output_text}, else: {:ok, text}
  end

  defp extract_output_text(body), do: {:error, {:unexpected_openai_response, body}}
end
