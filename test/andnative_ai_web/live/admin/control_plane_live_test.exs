defmodule AndnativeAiWeb.Admin.ControlPlaneLiveTest do
  use AndnativeAiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AndnativeAi.Memory
  alias AndnativeAi.Memory.Service
  alias AndnativeAi.Runtime.Audit

  setup :register_and_log_in_user

  test "fresh control plane shows status cards and an honest empty timeline", %{conn: conn} do
    tenant = Memory.ensure_demo_tenant!()

    {:ok, view, _html} = live(conn, ~p"/admin/control-plane")

    assert has_element?(view, "#control-plane-dashboard")
    assert has_element?(view, "#control-plane-appliance")
    assert has_element?(view, "#control-plane-status-grid")
    assert has_element?(view, "#status-card-slack-listener")
    assert has_element?(view, "#status-card-memory-service[data-status-mode='empty']")
    assert has_element?(view, "#status-card-openclaw-runtime")
    assert has_element?(view, "#status-card-document-source[data-status-mode='empty']")
    assert has_element?(view, "#status-card-runtime-activity[data-status-mode='empty']")
    assert has_element?(view, "#status-card-approval[data-status-mode='deferred']")
    assert has_element?(view, "#audit-timeline-empty")

    refute has_element?(view, "#control-plane-dashboard", "demo fallback")
    refute has_element?(view, "#control-plane-dashboard", "Demo fallback")
    refute has_element?(view, "#audit-timeline [data-audit-kind='memory_searched']")
    refute has_element?(view, "#audit-timeline [data-audit-kind='answer_generated']")
    refute has_element?(view, "#audit-timeline [data-audit-kind='citation_attached']")
    refute has_element?(view, "#audit-timeline [data-audit-kind='approval_paused']")

    assert tenant.name == "&native.ai"
  end

  test "control plane timeline includes live source lifecycle audit evidence", %{conn: conn} do
    tenant = Memory.ensure_demo_tenant!()

    {:ok, %{source: source}} =
      Service.ingest(
        tenant.id,
        %{
          source_type: "document",
          source_id: "handbook-#{System.unique_integer([:positive])}",
          name: "Demo handbook",
          permalink_or_url: "https://example.com/handbook"
        },
        ["Reimbursements above 500 require manager approval."],
        %{"permalink" => "https://example.com/handbook#expenses"},
        "tenant",
        "default"
      )

    {:ok, _result} = Service.delete_source(tenant.id, source.id)

    {:ok, view, _html} = live(conn, ~p"/admin/control-plane")

    assert has_element?(view, "#status-card-runtime-activity[data-status-mode='live']")
    assert has_element?(view, "#audit-timeline [data-audit-kind='source_ingested']")
    assert has_element?(view, "#audit-timeline [data-audit-kind='memory_indexed']")
    assert has_element?(view, "#audit-timeline [data-audit-kind='source_deleted']")
    assert has_element?(view, "#audit-timeline [data-audit-mode='live']")
    refute has_element?(view, "#audit-timeline [data-audit-mode='demo']")
  end

  test "control plane renders persisted runtime events with request and citation evidence", %{
    conn: conn
  } do
    tenant = Memory.ensure_demo_tenant!()

    {:ok, agent} =
      Memory.create_agent(tenant.id, %{
        name: "Alpha Agent",
        identity: "Answer from governed memory.",
        model: "gpt-4.1-mini",
        runtime: "openclaw",
        status: "active"
      })

    request_id = "req-alpha-123456"

    {:ok, _event} =
      Audit.record_event(%{
        tenant_id: tenant.id,
        agent_id: agent.id,
        request_id: request_id,
        event_kind: "memory_searched",
        component: "memory_tool",
        actor: agent.name,
        status: "ok",
        summary: "Alpha Agent searched governed memory.",
        metadata: %{result_count: 1}
      })

    {:ok, _event} =
      Audit.record_event(%{
        tenant_id: tenant.id,
        agent_id: agent.id,
        request_id: request_id,
        event_kind: "citation_attached",
        component: "openclaw_runtime",
        actor: agent.name,
        status: "attached",
        summary: "Alpha Agent attached governed memory citations.",
        metadata: %{citation_count: 1},
        citation_url: "https://example.com/handbook#expenses"
      })

    {:ok, view, _html} = live(conn, ~p"/admin/control-plane")

    assert has_element?(view, "#audit-timeline [data-audit-kind='memory_searched']")
    assert has_element?(view, "#audit-timeline [data-audit-kind='citation_attached']")
    assert has_element?(view, "#audit-timeline", "Alpha Agent searched governed memory.")
    assert has_element?(view, "#audit-timeline", "req req-alph")

    assert has_element?(
             view,
             "#audit-timeline a[href='https://example.com/handbook#expenses']"
           )

    refute has_element?(view, "#audit-timeline", "generated a concise response")
  end
end
