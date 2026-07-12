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
    assert has_element?(view, "#audit-timeline", "req-alpha-123456")
    refute has_element?(view, "#audit-timeline", "generated a concise response")

    # Selecting the citation event opens the inspector with the full request
    # trace and the citation link.
    view
    |> element("#audit-timeline [data-audit-kind='citation_attached'] button")
    |> render_click()

    assert has_element?(view, "#audit-event-inspector", "Citation attached")
    assert has_element?(view, "#audit-event-inspector", "req-alpha-123456")

    assert has_element?(
             view,
             "#audit-event-inspector a[href='https://example.com/handbook#expenses']"
           )

    assert has_element?(view, "#audit-request-trace", "Memory searched")
    assert has_element?(view, "#audit-request-trace", "Citation attached")

    view |> element("#close-audit-inspector") |> render_click()
    refute has_element?(view, "#audit-event-inspector")
  end

  test "control plane renders non-web citation evidence without crashing", %{conn: conn} do
    tenant = Memory.ensure_demo_tenant!()

    {:ok, _event} =
      Audit.record_event(%{
        tenant_id: tenant.id,
        event_kind: "citation_attached",
        component: "openclaw_runtime",
        actor: "Alpha Agent",
        status: "attached",
        summary: "Alpha Agent attached an internal Slack citation.",
        metadata: %{citation_count: 1},
        citation_url: "slack://channel/CDEMO"
      })

    {:ok, view, _html} = live(conn, ~p"/admin/control-plane")

    assert has_element?(
             view,
             "#audit-timeline",
             "Alpha Agent attached an internal Slack citation."
           )

    refute has_element?(view, "#audit-timeline a[href='slack://channel/CDEMO']")

    view
    |> element("#audit-timeline [data-audit-kind='citation_attached'] button")
    |> render_click()

    assert has_element?(view, "#audit-event-inspector", "Source recorded")
    refute has_element?(view, "#audit-event-inspector a[href='slack://channel/CDEMO']")
  end

  test "timeline filters by category and search query", %{conn: conn} do
    tenant = Memory.ensure_demo_tenant!()

    {:ok, _} =
      Audit.record_event(%{
        tenant_id: tenant.id,
        event_kind: "memory_searched",
        component: "memory_tool",
        actor: "Alpha Agent",
        status: "ok",
        summary: "Alpha Agent searched governed memory.",
        request_id: "req-filter-1"
      })

    {:ok, _} =
      Audit.record_event(%{
        tenant_id: tenant.id,
        event_kind: "source_deleted",
        component: "memory_service",
        actor: "Memory service",
        status: "deleted",
        summary: "Old handbook was removed from governed memory.",
        request_id: "req-filter-2"
      })

    {:ok, view, _html} = live(conn, ~p"/admin/control-plane")

    assert has_element?(view, "#audit-timeline [data-audit-kind='memory_searched']")
    assert has_element?(view, "#audit-timeline [data-audit-kind='source_deleted']")

    view |> element("#audit-filter-governance") |> render_click()

    refute has_element?(view, "#audit-timeline [data-audit-kind='memory_searched']")
    assert has_element?(view, "#audit-timeline [data-audit-kind='source_deleted']")

    view |> element("#audit-filter-all") |> render_click()
    assert has_element?(view, "#audit-timeline [data-audit-kind='memory_searched']")

    view
    |> form("#audit-search-form", %{"q" => "req-filter-1"})
    |> render_change()

    assert has_element?(view, "#audit-timeline [data-audit-kind='memory_searched']")
    refute has_element?(view, "#audit-timeline [data-audit-kind='source_deleted']")

    view
    |> form("#audit-search-form", %{"q" => "no-such-request"})
    |> render_change()

    assert has_element?(view, "#audit-timeline-no-match")
  end

  test "timeline streams newly recorded audit events live", %{conn: conn} do
    tenant = Memory.ensure_demo_tenant!()

    {:ok, view, _html} = live(conn, ~p"/admin/control-plane")

    assert has_element?(view, "#audit-timeline-empty")

    {:ok, _} =
      Audit.record_event(%{
        tenant_id: tenant.id,
        event_kind: "answer_generated",
        component: "openclaw_runtime",
        actor: "Alpha Agent",
        status: "ok",
        summary: "Alpha Agent generated a governed answer.",
        request_id: "req-live-1"
      })

    assert render(view) =~ "Alpha Agent generated a governed answer."
    assert has_element?(view, "#audit-timeline [data-audit-kind='answer_generated']")
    refute has_element?(view, "#audit-timeline-empty")
  end

  test "timeline paginates older events with load more", %{conn: conn} do
    tenant = Memory.ensure_demo_tenant!()

    for index <- 1..30 do
      {:ok, _} =
        Audit.record_event(%{
          tenant_id: tenant.id,
          event_kind: "memory_indexed",
          component: "memory_service",
          actor: "Memory service",
          status: "indexed",
          summary: "Chunk #{index} indexed into governed memory.",
          request_id: "req-page-#{index}"
        })
    end

    {:ok, view, _html} = live(conn, ~p"/admin/control-plane")

    assert has_element?(view, "#audit-load-more")
    refute has_element?(view, "#audit-timeline", "Chunk 1 indexed")

    view |> element("#audit-load-more") |> render_click()

    assert has_element?(view, "#audit-timeline", "Chunk 1 indexed")
    refute has_element?(view, "#audit-load-more")
  end
end
