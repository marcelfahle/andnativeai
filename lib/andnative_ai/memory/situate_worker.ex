defmodule AndnativeAi.Memory.SituateWorker do
  @moduledoc """
  Contextual chunk situating (Anthropic "Contextual Retrieval"): for each
  chunk of a document source, an LLM writes a 1-2 sentence line situating
  the chunk within the whole document; the chunk is re-embedded as
  `context + text`. Runs asynchronously after ingest so uploads stay fast,
  and only when an OpenAI key is configured.
  """

  use Oban.Worker, queue: :memory, max_attempts: 3

  require Logger

  import Ecto.Query

  alias AndnativeAi.Memory
  alias AndnativeAi.Memory.{Embeddings, Item}
  alias AndnativeAi.Repo
  alias AndnativeAi.Runtime.OpenAIClient

  def enabled? do
    api_key = System.get_env("OPENAI_API_KEY", "")
    api_key != "" and not String.contains?(api_key, "replace-me")
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"source_id" => source_id, "tenant_id" => tenant_id}}) do
    source = Memory.get_source!(tenant_id, source_id)
    items = Memory.list_source_memory_items(tenant_id, source_id)
    document = document_text(items)

    Enum.each(items, fn item ->
      case situate(document, source, item) do
        {:ok, context} ->
          item
          |> Item.changeset(%{
            context: context,
            embedding: Embeddings.embed(context <> "\n" <> item.text)
          })
          |> Repo.update!()

        {:error, reason} ->
          # Leave the chunk as ingested; situating is an upgrade, not a
          # requirement.
          Logger.warning("Chunk situating skipped for item #{item.id}: #{inspect(reason)}")
      end
    end)

    :ok
  end

  def enqueue(tenant_id, source_id) do
    %{tenant_id: tenant_id, source_id: source_id}
    |> new()
    |> Oban.insert()
  end

  @doc """
  Re-embeds every active memory item with the currently configured
  embedding provider (context included when present). Used when switching
  providers; invoked from `AndnativeAi.Release.reembed_memory/0`.
  """
  def reembed_all(tenant_id) do
    items =
      Repo.all(
        from item in Item,
          where: item.tenant_id == ^tenant_id and is_nil(item.deleted_at)
      )

    Enum.each(items, fn item ->
      text = if item.context, do: item.context <> "\n" <> item.text, else: item.text

      item
      |> Item.changeset(%{embedding: Embeddings.embed(text)})
      |> Repo.update!()
    end)

    length(items)
  end

  defp document_text(items) do
    stored_path = source_stored_path(items)

    case stored_path && File.read(stored_path) do
      {:ok, text} -> String.slice(text, 0, 24_000)
      _unavailable -> items |> Enum.map_join("\n\n", & &1.text) |> String.slice(0, 24_000)
    end
  end

  defp source_stored_path(items) do
    Enum.find_value(items, fn item -> item.provenance["stored_path"] end)
  end

  defp situate(document, source, item) do
    api_key = System.get_env("OPENAI_API_KEY", "")

    openai_client().response(%{
      api_key: api_key,
      model: System.get_env("OPENAI_CHAT_MODEL", "gpt-4.1-mini"),
      instructions: """
      You situate a chunk within its source document for retrieval.
      Reply with one or two short sentences stating what document the chunk
      is from and what it covers. No preamble.
      """,
      input: """
      Document: #{source.name}

      Full document (may be truncated):
      #{document}

      Chunk:
      #{String.slice(item.text, 0, 2_000)}
      """,
      max_output_tokens: 120
    })
  end

  defp openai_client do
    Application.get_env(:andnative_ai, :openai_client, OpenAIClient)
  end
end
