defmodule AndnativeAi.Runtime.MemoryTool do
  alias AndnativeAi.Memory.Service

  def schema do
    %{
      name: "memory_search",
      description: "Search governed external memory for a tenant before answering.",
      input_schema: %{
        type: "object",
        required: ["tenant_id", "query"],
        properties: %{
          tenant_id: %{type: "integer"},
          query: %{type: "string"},
          limit: %{type: "integer", default: 3},
          collection_id: %{
            type: "integer",
            description: "Restrict the search to one collection"
          }
        }
      }
    }
  end

  def call(%{"tenant_id" => tenant_id, "query" => query} = args) do
    scope =
      %{limit: Map.get(args, "limit", 3)}
      |> put_collection(Map.get(args, "collection_id"))

    {:ok, Service.search(tenant_id, query, scope)}
  end

  def call(%{tenant_id: tenant_id, query: query} = args) do
    scope =
      %{limit: Map.get(args, :limit, 3)}
      |> put_collection(Map.get(args, :collection_id))

    {:ok, Service.search(tenant_id, query, scope)}
  end

  def call(_args), do: {:error, :invalid_memory_search_args}

  defp put_collection(scope, collection_id) when is_integer(collection_id),
    do: Map.put(scope, :collection_id, collection_id)

  defp put_collection(scope, collection_id) when is_binary(collection_id) do
    case Integer.parse(collection_id) do
      {id, ""} -> Map.put(scope, :collection_id, id)
      _invalid -> scope
    end
  end

  defp put_collection(scope, _collection_id), do: scope
end
