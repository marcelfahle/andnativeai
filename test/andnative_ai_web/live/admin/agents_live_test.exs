defmodule AndnativeAiWeb.Admin.AgentsLiveTest do
  use AndnativeAiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AndnativeAi.Memory

  setup do
    workspace =
      Path.join(
        System.tmp_dir!(),
        "andnative-admin-openclaw-#{System.unique_integer([:positive])}"
      )

    previous_workspace = Application.get_env(:andnative_ai, :openclaw_workspace_path)
    Application.put_env(:andnative_ai, :openclaw_workspace_path, workspace)

    on_exit(fn ->
      if previous_workspace do
        Application.put_env(:andnative_ai, :openclaw_workspace_path, previous_workspace)
      else
        Application.delete_env(:andnative_ai, :openclaw_workspace_path)
      end

      File.rm_rf(workspace)
    end)

    :ok
  end

  test "a demo user can create and sync an OpenClaw agent", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/agents")

    view
    |> form("#agent-form",
      agent: %{
        name: "Demo Agent",
        identity: "Answer from governed memory.",
        model: "gpt-4.1-mini",
        status: "active"
      }
    )
    |> render_submit()

    assert has_element?(view, "#agents-list [id^='agent-']")

    tenant = Memory.ensure_demo_tenant!()
    [agent | _] = Memory.list_agents(tenant.id)

    view
    |> element("#sync-agent-#{agent.id}")
    |> render_click()

    synced_agent = Memory.get_agent!(tenant.id, agent.id)
    assert synced_agent.runtime_ref
    assert File.exists?(synced_agent.runtime_ref)
  end

  test "admin navigation exposes sources, Slack, and runtime pages", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/agents")

    assert has_element?(view, "a[href='/admin/sources']")
    assert has_element?(view, "a[href='/admin/slack']")
    assert has_element?(view, "a[href='/admin/runtime']")
  end
end
