defmodule AndnativeAiWeb.Admin.AgentsLiveTest do
  use AndnativeAiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AndnativeAi.Accounts
  alias AndnativeAi.Memory
  alias AndnativeAi.Runtime.Audit

  setup :register_and_log_in_user

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
        role: "marketing",
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
    assert synced_agent.role == "marketing"
    assert synced_agent.runtime_ref
    assert File.exists?(synced_agent.runtime_ref)
  end

  test "ordinary admins see roles but never models or the policy panel", %{conn: conn} do
    tenant = Memory.ensure_demo_tenant!()

    {:ok, agent} =
      Memory.create_agent(tenant.id, %{
        "name" => "Bran",
        "identity" => "Marketing copilot.",
        "role" => "marketing",
        "status" => "active"
      })

    {:ok, _agent} =
      Memory.update_agent_model_policy(agent, %{"model" => "gpt-5.6-terra"})

    {:ok, view, html} = live(conn, ~p"/admin/agents")

    assert html =~ "Marketing"
    refute html =~ "gpt-5.6-terra"
    refute has_element?(view, "#agent-model-#{agent.id}")
    refute has_element?(view, "#policy-agent-#{agent.id}")
    refute has_element?(view, "select#agent_model")
  end

  test "superadmins see effective models and set audited policy", %{conn: conn, user: user} do
    {:ok, _superadmin} = Accounts.set_user_role(user, "superadmin")
    tenant = Memory.ensure_demo_tenant!()

    {:ok, agent} =
      Memory.create_agent(tenant.id, %{
        "name" => "Bran",
        "identity" => "Marketing copilot.",
        "role" => "marketing",
        "status" => "active"
      })

    {:ok, view, _html} = live(conn, ~p"/admin/agents")

    assert has_element?(view, "#agent-model-#{agent.id}")

    view
    |> element("#policy-agent-#{agent.id}")
    |> render_click()

    assert has_element?(view, "#model-policy-panel")

    view
    |> form("#model-policy-form",
      policy: %{
        model: "gpt-5.6-terra",
        write: "claude-opus-4-8",
        chat: "",
        classify: "",
        situate: ""
      }
    )
    |> render_submit()

    updated = Memory.get_agent!(tenant.id, agent.id)
    assert updated.model == "gpt-5.6-terra"
    assert updated.model_policy == %{"write" => "claude-opus-4-8"}

    assert Enum.any?(
             Audit.list_recent_events(tenant.id, limit: 10),
             &(&1.event_kind == "model_policy_changed" and &1.actor == user.email)
           )
  end

  test "admin navigation exposes sources, Slack, and runtime pages", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/agents")

    assert has_element?(view, "a[href='/admin/control-plane']")
    assert has_element?(view, "a[href='/admin/sources']")
    assert has_element?(view, "a[href='/admin/slack']")
    assert has_element?(view, "a[href='/admin/runtime']")
  end
end
