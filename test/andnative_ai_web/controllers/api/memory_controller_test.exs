defmodule AndnativeAiWeb.Api.MemoryControllerTest do
  use AndnativeAiWeb.ConnCase, async: true

  alias AndnativeAi.Memory
  alias AndnativeAi.Memory.Service

  test "POST /api/memory/search exposes the memory search tool", %{conn: conn} do
    {:ok, tenant} =
      Memory.create_tenant(%{
        name: "API Tenant",
        slug: "api-tenant",
        status: "active"
      })

    {:ok, _result} =
      Service.ingest(
        tenant.id,
        %{
          source_type: "document",
          source_id: "api-doc",
          name: "api-doc.md",
          permalink_or_url: "https://docs.example.com/api-doc"
        },
        ["API memory search should cite its document source."],
        %{"permalink" => "https://docs.example.com/api-doc"},
        "tenant",
        "default"
      )

    conn =
      post(conn, ~p"/api/memory/search", %{
        tenant_id: tenant.id,
        query: "memory citation",
        limit: 1
      })

    assert %{"results" => [%{"source" => %{"name" => "api-doc.md"}, "citation_url" => citation}]} =
             json_response(conn, 200)

    assert citation == "https://docs.example.com/api-doc"
  end
end
