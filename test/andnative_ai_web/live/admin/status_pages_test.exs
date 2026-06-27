defmodule AndnativeAiWeb.Admin.StatusPagesTest do
  use AndnativeAiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AndnativeAi.Memory

  test "sources and Slack pages show Slack channel ingestion status", %{conn: conn} do
    tenant = Memory.ensure_demo_tenant!()

    {:ok, _source} =
      Memory.upsert_source(tenant.id, %{
        source_type: "slack_channel",
        source_id: "CDEMO",
        name: "Slack CDEMO",
        permalink_or_url: "slack://channel/CDEMO",
        status: "ready"
      })

    {:ok, sources_view, _html} = live(conn, ~p"/admin/sources")
    assert has_element?(sources_view, "#slack-source-list [id^='source-']")

    {:ok, slack_view, _html} = live(conn, ~p"/admin/slack")
    assert has_element?(slack_view, "#slack-channels [id^='slack-source-']")
    assert has_element?(slack_view, "#slack-connection-status")
  end

  test "runtime page shows OpenClaw health without raw gateway controls", %{conn: conn} do
    tenant = Memory.ensure_demo_tenant!()

    {:ok, _agent} =
      Memory.create_agent(tenant.id, %{
        name: "Runtime Agent",
        identity: "Answer from governed memory.",
        model: "gpt-4.1-mini",
        runtime: "openclaw",
        status: "active"
      })

    {:ok, view, _html} = live(conn, ~p"/admin/runtime")

    assert has_element?(view, "#runtime-agents [id^='runtime-agent-']")
    refute render(view) =~ "gateway admin"
  end
end
