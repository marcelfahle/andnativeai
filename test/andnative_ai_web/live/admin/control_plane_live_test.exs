defmodule AndnativeAiWeb.Admin.ControlPlaneLiveTest do
  use AndnativeAiWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias AndnativeAi.Memory.Agent
  alias AndnativeAi.Memory
  alias AndnativeAi.Repo

  test "control plane shows appliance status cards and runtime trust timeline", %{conn: conn} do
    tenant = Memory.ensure_demo_tenant!()
    source_id = "handbook-#{System.unique_integer([:positive])}"

    {:ok, source} =
      Memory.create_source(tenant.id, %{
        source_type: "document",
        source_id: source_id,
        name: "Demo handbook",
        permalink_or_url: "https://example.com/handbook",
        status: "ready",
        last_ingested_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    {:ok, _item} =
      Memory.create_memory_item(tenant.id, source, %{
        source_type: "document",
        text: "Reimbursements above 500 require manager approval.",
        provenance: %{"permalink" => "https://example.com/handbook#expenses"},
        visibility: "tenant",
        retention_class: "default"
      })

    {:ok, view, _html} = live(conn, ~p"/admin/control-plane")

    assert has_element?(view, "#control-plane-dashboard")
    assert has_element?(view, "#control-plane-appliance")
    assert has_element?(view, "#status-card-slack-listener")
    assert has_element?(view, "#status-card-memory-service[data-status-mode='live']")
    assert has_element?(view, "#status-card-openclaw-runtime")
    assert has_element?(view, "#status-card-document-source[data-status-mode='live']")
    assert has_element?(view, "#status-card-slack-source")
    assert has_element?(view, "#status-card-approval[data-status-mode='demo']")
    assert has_element?(view, "#audit-timeline [data-audit-mode='live']")
    assert has_element?(view, "#audit-timeline [data-audit-mode='demo']")
    assert has_element?(view, "#audit-timeline [data-audit-kind='memory_searched']")
    assert has_element?(view, "#audit-timeline [data-audit-kind='answer_generated']")
    assert has_element?(view, "#audit-timeline [data-audit-kind='citation_attached']")
    assert has_element?(view, "#audit-timeline [data-audit-kind='approval_paused']")
  end

  test "control plane timeline includes live source deletion audit evidence", %{conn: conn} do
    tenant = Memory.ensure_demo_tenant!()
    source_id = "stale-source-#{System.unique_integer([:positive])}"

    {:ok, source} =
      Memory.create_source(tenant.id, %{
        source_type: "document",
        source_id: source_id,
        name: "Expired guide",
        permalink_or_url: "https://example.com/expired",
        status: "ready",
        last_ingested_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    {:ok, _result} = Memory.soft_delete_source(tenant.id, source.id)

    {:ok, view, _html} = live(conn, ~p"/admin/control-plane")

    assert has_element?(view, "#audit-event-source-deleted-#{source.id}")
    assert has_element?(view, "#audit-timeline [data-audit-kind='source_deleted']")
  end

  test "control plane demo events use the most recently updated agent", %{conn: conn} do
    tenant = Memory.ensure_demo_tenant!()

    {:ok, old_agent} =
      Memory.create_agent(tenant.id, %{
        name: "Zulu Agent",
        identity: "Old agent.",
        model: "gpt-4.1-mini",
        runtime: "openclaw",
        status: "active"
      })

    {:ok, new_agent} =
      Memory.create_agent(tenant.id, %{
        name: "Alpha Agent",
        identity: "New agent.",
        model: "gpt-4.1-mini",
        runtime: "openclaw",
        status: "active"
      })

    old_time = ~U[2026-01-01 00:00:00Z]
    new_time = ~U[2026-01-02 00:00:00Z]

    from(agent in Agent, where: agent.id == ^old_agent.id)
    |> Repo.update_all(set: [inserted_at: old_time, updated_at: old_time])

    from(agent in Agent, where: agent.id == ^new_agent.id)
    |> Repo.update_all(set: [inserted_at: new_time, updated_at: new_time])

    {:ok, view, _html} = live(conn, ~p"/admin/control-plane")
    html = render(view)

    assert html =~ "Alpha Agent generated a concise response"
    refute html =~ "Zulu Agent generated a concise response"
  end
end
