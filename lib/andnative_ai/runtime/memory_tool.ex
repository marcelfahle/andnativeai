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
          limit: %{type: "integer", default: 3}
        }
      }
    }
  end

  def call(%{"tenant_id" => tenant_id, "query" => query} = args) do
    limit = Map.get(args, "limit", 3)
    {:ok, Service.search(tenant_id, query, %{limit: limit})}
  end

  def call(%{tenant_id: tenant_id, query: query} = args) do
    limit = Map.get(args, :limit, 3)
    {:ok, Service.search(tenant_id, query, %{limit: limit})}
  end

  def call(_args), do: {:error, :invalid_memory_search_args}
end
