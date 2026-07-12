defmodule AndnativeAi.Memory.Embeddings.OpenAI do
  @moduledoc """
  Provider embeddings via OpenAI `text-embedding-3-small` at the corpus's
  1536 dimensions. On API failure this falls back to the deterministic
  embedder with a loud log — a degraded ranking beats a crashed ingest,
  and the lexical rerank still rejects unrelated results.
  """

  require Logger

  alias AndnativeAi.Memory.Embeddings

  @api "https://api.openai.com/v1/embeddings"

  def embed(text) when is_binary(text) do
    case request(text) do
      {:ok, vector} ->
        Pgvector.new(vector)

      {:error, reason} ->
        Logger.error(
          "OpenAI embedding failed (#{inspect(reason)}); falling back to deterministic embedding for this text"
        )

        Embeddings.Deterministic.embed(text)
    end
  end

  defp request(text) do
    api_key = System.get_env("OPENAI_API_KEY", "")

    body = %{
      model: System.get_env("OPENAI_EMBEDDING_MODEL", "text-embedding-3-small"),
      input: String.slice(text, 0, 8_000),
      dimensions: Embeddings.dimensions()
    }

    [
      method: :post,
      url: @api,
      auth: {:bearer, api_key},
      json: body,
      receive_timeout: 30_000
    ]
    |> Req.request()
    |> case do
      {:ok, %{status: 200, body: %{"data" => [%{"embedding" => vector} | _]}}} ->
        {:ok, vector}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
