defmodule AndnativeAiWeb.Admin.ProspectPlansLiveTest do
  use AndnativeAiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AndnativeAi.Memory
  alias AndnativeAi.Prospects

  setup :register_and_log_in_user

  test "creates a plan from the discover form and shows the preview", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/prospects")

    assert has_element?(view, "#prospect-plans-empty")

    view
    |> form("#prospect-plan-form", %{
      prospect_plan: %{
        company_name: "Acme GmbH",
        sector: "Manufacturing",
        workflow_pain: "Policy questions interrupt the ops lead a dozen times a week.",
        systems: "Slack, Notion",
        manual_steps: "Look up the policy in Notion",
        risk_notes: "HR documents contain personal data",
        success_metric: "Ops-lead interruptions per week"
      }
    })
    |> render_submit()

    tenant = Memory.ensure_demo_tenant!()
    assert [plan] = Prospects.list_plans(tenant.id)

    {:ok, preview, _html} = live(conn, ~p"/admin/prospects/#{plan.id}")

    assert has_element?(preview, "#prospect-plan-preview", "Acme GmbH")
    assert has_element?(preview, "#plan-pain", "Policy questions interrupt")
    assert has_element?(preview, "#plan-sources", "Slack channels")
    assert has_element?(preview, "#plan-governance", "HR documents contain personal data")
    assert has_element?(preview, "#plan-metric", "Ops-lead interruptions per week")
    assert has_element?(preview, "#plan-roadmap", "First 30 days")
    assert has_element?(preview, "#prospect-plan-preview", "proposal, not a commitment")
  end

  test "validates required fields inline", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/prospects")

    html =
      view
      |> form("#prospect-plan-form", %{prospect_plan: %{company_name: "", workflow_pain: ""}})
      |> render_change()

    assert html =~ "can&#39;t be blank"

    # Submitting the invalid form keeps the errors and creates nothing.
    assert render_submit(form(view, "#prospect-plan-form")) =~ "can&#39;t be blank"
  end

  test "deletes a plan from the list", %{conn: conn} do
    tenant = Memory.ensure_demo_tenant!()

    {:ok, plan} =
      Prospects.create_plan(tenant.id, %{
        "company_name" => "Acme GmbH",
        "workflow_pain" => "Something painful"
      })

    {:ok, view, _html} = live(conn, ~p"/admin/prospects")

    view
    |> element("#delete-plan-#{plan.id}")
    |> render_click()

    assert has_element?(view, "#prospect-plans-empty")
    assert Prospects.list_plans(tenant.id) == []
  end
end
