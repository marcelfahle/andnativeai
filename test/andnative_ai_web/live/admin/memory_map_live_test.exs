defmodule AndnativeAiWeb.Admin.MemoryMapLiveTest do
  use AndnativeAiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AndnativeAi.Memory
  alias AndnativeAi.Memory.Service

  setup :register_and_log_in_user

  test "empty memory map teaches how to add sources", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/memory")

    assert has_element?(view, "#memory-map")
    assert has_element?(view, "#memory-scope-layers")
    assert has_element?(view, "#memory-scope-layers", "planned")
    assert has_element?(view, "#memory-group-slack-empty")
    assert has_element?(view, "#memory-group-documents-empty")
    assert has_element?(view, "#memory-group-connectors", "planned")
  end

  test "groups sources by type with chunk counts and expandable items", %{conn: conn} do
    tenant = Memory.ensure_demo_tenant!()

    {:ok, %{source: document}} =
      Service.ingest(
        tenant.id,
        %{
          source_type: "document",
          source_id: "handbook-map",
          name: "Employee handbook.md",
          permalink_or_url: "https://example.com/handbook"
        },
        [
          "Reimbursements above 500 require manager approval.",
          "Remote work is allowed up to 3 days per week."
        ],
        %{"permalink" => "https://example.com/handbook#expenses"},
        "tenant",
        "default"
      )

    {:ok, _} =
      Service.ingest(
        tenant.id,
        %{
          source_type: "slack_channel",
          source_id: "CMAP123",
          name: "#general",
          permalink_or_url: "slack://channel/CMAP123"
        },
        ["We decided to launch the pilot on July 20."],
        %{"slack_channel" => "CMAP123"},
        "tenant",
        "default"
      )

    {:ok, view, _html} = live(conn, ~p"/admin/memory")

    assert has_element?(view, "#memory-group-documents", "Employee handbook.md")
    assert has_element?(view, "#memory-group-slack", "#general")
    assert has_element?(view, "#memory-source-#{document.id}", "active in retrieval")

    view
    |> element("#memory-source-#{document.id} > button")
    |> render_click()

    assert has_element?(view, "#memory-source-items-#{document.id}")
    assert has_element?(view, "#memory-source-items-#{document.id}", "Reimbursements above 500")

    assert has_element?(
             view,
             "#memory-source-items-#{document.id} a[href='https://example.com/handbook#expenses']"
           )
  end

  test "deleted sources stay visible but marked excluded from retrieval", %{conn: conn} do
    tenant = Memory.ensure_demo_tenant!()

    {:ok, %{source: source}} =
      Service.ingest(
        tenant.id,
        %{
          source_type: "document",
          source_id: "obsolete-map",
          name: "Old policy.md",
          permalink_or_url: "https://example.com/old-policy"
        },
        ["The obsolete refund policy required no approval."],
        %{"permalink" => "https://example.com/old-policy"},
        "tenant",
        "default"
      )

    {:ok, _} = Service.delete_source(tenant.id, source.id)

    {:ok, view, _html} = live(conn, ~p"/admin/memory")

    assert has_element?(view, "#memory-source-#{source.id}", "Old policy.md")
    assert has_element?(view, "#memory-source-#{source.id}", "excluded from retrieval")
    refute has_element?(view, "#memory-source-#{source.id}", "active in retrieval")

    view
    |> element("#memory-source-#{source.id} > button")
    |> render_click()

    assert has_element?(view, "#memory-source-items-#{source.id}", "deleted")
  end
end
