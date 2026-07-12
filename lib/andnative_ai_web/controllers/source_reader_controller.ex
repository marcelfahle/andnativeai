defmodule AndnativeAiWeb.SourceReaderController do
  use AndnativeAiWeb, :controller

  alias AndnativeAi.Memory

  @doc """
  The page a Slack citation opens: the cited source rendered as a
  readable document, not an audit screen. Requires a logged-in workspace
  member (routed through `require_authenticated_user`).
  """
  def show(conn, %{"id" => raw_id}) do
    tenant = Memory.ensure_demo_tenant!()

    with {id, ""} <- Integer.parse(raw_id),
         %{deleted_at: nil} = source <- get_live_source(tenant.id, id),
         {:ok, markdown} <- source_markdown(tenant.id, source),
         # MDEx omits raw HTML blocks by default, so uploaded documents
         # cannot inject script into the reader.
         {:ok, document_html} <- MDEx.to_html(markdown) do
      render(conn, :show,
        page_title: source.name,
        source: source,
        collection: source_collection(tenant.id, source),
        document_html: document_html
      )
    else
      _not_found ->
        conn
        |> put_status(:not_found)
        |> put_view(AndnativeAiWeb.ErrorHTML)
        |> render("404.html")
    end
  end

  defp get_live_source(tenant_id, id) do
    AndnativeAi.Repo.get_by(Memory.Source, id: id, tenant_id: tenant_id)
  end

  # Prefer the stored raw file (real markdown); fall back to the ingested
  # chunks so Slack-channel sources and sources whose file moved still read.
  defp source_markdown(tenant_id, source) do
    case stored_file_markdown(tenant_id, source) do
      {:ok, markdown} -> {:ok, markdown}
      :error -> chunk_markdown(tenant_id, source)
    end
  end

  defp stored_file_markdown(tenant_id, source) do
    with [item | _rest] <- Memory.list_source_memory_items(tenant_id, source.id),
         path when is_binary(path) <- item.provenance["stored_path"],
         {:ok, markdown} <- File.read(path) do
      {:ok, markdown}
    else
      _unavailable -> :error
    end
  end

  defp chunk_markdown(tenant_id, source) do
    case Memory.list_source_memory_items(tenant_id, source.id) do
      [] -> :error
      items -> {:ok, items |> Enum.map(& &1.text) |> Enum.join("\n\n---\n\n")}
    end
  end

  defp source_collection(_tenant_id, %{collection_id: nil}), do: nil

  defp source_collection(tenant_id, source) do
    tenant_id
    |> Memory.list_collections()
    |> Enum.find(&(&1.id == source.collection_id))
  end
end
