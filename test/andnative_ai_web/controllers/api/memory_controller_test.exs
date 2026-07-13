defmodule AndnativeAiWeb.Api.MemoryControllerTest do
  use AndnativeAiWeb.ConnCase, async: false

  alias AndnativeAi.Memory
  alias AndnativeAi.Memory.Service

  @token "test-memory-tool-token"

  setup do
    previous = System.get_env("MEMORY_TOOL_TOKEN")
    System.put_env("MEMORY_TOOL_TOKEN", @token)

    on_exit(fn ->
      if previous,
        do: System.put_env("MEMORY_TOOL_TOKEN", previous),
        else: System.delete_env("MEMORY_TOOL_TOKEN")
    end)

    :ok
  end

  defp authed(conn), do: put_req_header(conn, "authorization", "Bearer " <> @token)

  test "the memory API is never reachable without the shared token", %{conn: conn} do
    # No credentials at all.
    assert conn
           |> post(~p"/api/memory/search", %{tenant_id: 1, query: "anything"})
           |> json_response(401)

    # Wrong token.
    assert conn
           |> put_req_header("authorization", "Bearer wrong-token")
           |> post(~p"/api/memory/search", %{tenant_id: 1, query: "anything"})
           |> json_response(401)
  end

  test "it fails closed when no token is configured", %{conn: conn} do
    System.delete_env("MEMORY_TOOL_TOKEN")

    assert conn
           |> authed()
           |> post(~p"/api/memory/search", %{tenant_id: 1, query: "anything"})
           |> json_response(401)
  end

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
      post(authed(conn), ~p"/api/memory/search", %{
        tenant_id: tenant.id,
        query: "memory citation",
        limit: 1
      })

    assert %{"results" => [%{"source" => %{"name" => "api-doc.md"}, "citation_url" => citation}]} =
             json_response(conn, 200)

    assert citation == "https://docs.example.com/api-doc"
  end
end
