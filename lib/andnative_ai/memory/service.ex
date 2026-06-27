defmodule AndnativeAi.Memory.Service do
  import Ecto.Query
  import Pgvector.Ecto.Query

  alias AndnativeAi.Memory
  alias AndnativeAi.Memory.{Embeddings, Item, Source}
  alias AndnativeAi.Repo

  def ingest(tenant_id, source_attrs, chunks, provenance, visibility, retention) do
    Repo.transaction(fn ->
      source = upsert_source!(tenant_id, source_attrs)

      items =
        Enum.map(chunks, fn chunk ->
          chunk = normalize_chunk(chunk)
          text = Map.fetch!(chunk, :text)

          item_attrs = %{
            text: text,
            embedding: Embeddings.embed(text),
            provenance: merge_provenance(provenance, Map.get(chunk, :provenance, %{})),
            visibility: visibility,
            retention_class: retention_class(retention),
            expires_at: retention_expires_at(retention),
            channel_id: Map.get(chunk, :channel_id)
          }

          {:ok, item} = Memory.create_memory_item(tenant_id, source, item_attrs)
          item
        end)

      source =
        source
        |> Source.changeset(%{status: "ready", last_ingested_at: utc_now()})
        |> Repo.update!()

      %{source: source, items: items}
    end)
  end

  def search(tenant_id, query, scope \\ %{}) when is_binary(query) do
    limit = Map.get(scope, :limit, 5)
    query_embedding = Embeddings.embed(query)

    Item
    |> join(:inner, [item], source in assoc(item, :source))
    |> where([item, source], item.tenant_id == ^tenant_id and source.tenant_id == ^tenant_id)
    |> where([item, source], is_nil(item.deleted_at) and is_nil(source.deleted_at))
    |> where([item], not is_nil(item.embedding))
    |> apply_scope(scope)
    |> order_by([item], asc: cosine_distance(item.embedding, ^query_embedding))
    |> limit(^limit)
    |> select([item, source], %{
      id: item.id,
      text: item.text,
      score: fragment("1.0 - (? <=> ?)", item.embedding, ^query_embedding),
      provenance: item.provenance,
      citation_url:
        fragment(
          "COALESCE(NULLIF(?->>'permalink', ''), ?)",
          item.provenance,
          source.permalink_or_url
        ),
      source: %{
        id: source.id,
        type: source.source_type,
        external_id: source.source_id,
        name: source.name,
        url: source.permalink_or_url
      }
    })
    |> Repo.all()
  end

  def delete_source(tenant_id, source_id), do: Memory.soft_delete_source(tenant_id, source_id)

  defp upsert_source!(tenant_id, attrs) do
    attrs =
      attrs
      |> atomize_known_keys()
      |> Map.merge(%{status: "ingesting", deleted_at: nil})

    case Memory.upsert_source(tenant_id, attrs) do
      {:ok, source} ->
        source

      {:error, changeset} ->
        raise Ecto.InvalidChangesetError, action: :insert, changeset: changeset
    end
  end

  defp normalize_chunk(chunk) when is_binary(chunk), do: %{text: chunk}

  defp normalize_chunk(chunk) when is_map(chunk) do
    chunk
    |> atomize_known_keys()
    |> Map.update(:provenance, %{}, &Map.new/1)
  end

  defp atomize_known_keys(map) do
    Enum.reduce(map, %{}, fn
      {key, value}, acc when is_atom(key) ->
        Map.put(acc, key, value)

      {key, value}, acc
      when key in ~w(source_type source_id name permalink_or_url status text provenance channel_id) ->
        Map.put(acc, String.to_existing_atom(key), value)

      {_key, _value}, acc ->
        acc
    end)
  end

  defp merge_provenance(base, chunk) do
    base
    |> Map.new()
    |> Map.merge(Map.new(chunk))
  end

  defp retention_class(retention) when is_binary(retention), do: retention

  defp retention_class(retention) when is_map(retention),
    do: Map.get(retention, :class, "default")

  defp retention_class(_retention), do: "default"

  defp retention_expires_at(retention) when is_map(retention), do: Map.get(retention, :expires_at)
  defp retention_expires_at(_retention), do: nil

  defp apply_scope(query, scope) do
    Enum.reduce(scope, query, fn
      {:source_type, source_type}, query ->
        where(query, [item, _source], item.source_type == ^source_type)

      {:source_types, source_types}, query ->
        where(query, [item, _source], item.source_type in ^source_types)

      {:source_id, source_id}, query ->
        where(query, [_item, source], source.id == ^source_id)

      {:channel_id, channel_id}, query ->
        where(query, [item, _source], item.channel_id == ^channel_id)

      {:limit, _limit}, query ->
        query

      {_key, _value}, query ->
        query
    end)
  end

  defp utc_now do
    DateTime.utc_now() |> DateTime.truncate(:second)
  end
end
