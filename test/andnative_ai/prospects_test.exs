defmodule AndnativeAi.ProspectsTest do
  use AndnativeAi.DataCase, async: true

  alias AndnativeAi.Memory
  alias AndnativeAi.Prospects
  alias AndnativeAi.Prospects.PlanBuilder

  defp tenant_fixture(slug) do
    {:ok, tenant} =
      Memory.create_tenant(%{name: String.upcase(slug), slug: slug, status: "active"})

    tenant
  end

  test "creates, lists, and deletes tenant-scoped plans" do
    tenant = tenant_fixture("prospects")
    other = tenant_fixture("prospects-other")

    {:ok, plan} =
      Prospects.create_plan(tenant.id, %{
        "company_name" => "Acme GmbH",
        "workflow_pain" => "Answering policy questions interrupts the ops lead."
      })

    {:ok, _other_plan} =
      Prospects.create_plan(other.id, %{
        "company_name" => "Elsewhere AG",
        "workflow_pain" => "Different tenant"
      })

    assert [%{id: listed_id}] = Prospects.list_plans(tenant.id)
    assert listed_id == plan.id

    assert Prospects.get_plan!(tenant.id, plan.id).company_name == "Acme GmbH"
    assert_raise Ecto.NoResultsError, fn -> Prospects.get_plan!(other.id, plan.id) end

    {:ok, _} = Prospects.delete_plan(plan)
    assert Prospects.list_plans(tenant.id) == []
  end

  test "requires company name and workflow pain" do
    tenant = tenant_fixture("prospects-required")

    {:error, changeset} = Prospects.create_plan(tenant.id, %{})
    assert %{company_name: _, workflow_pain: _} = errors_on(changeset)
  end

  describe "PlanBuilder" do
    test "maps systems to source connections with honest planned states" do
      tenant = tenant_fixture("prospects-builder")

      {:ok, plan} =
        Prospects.create_plan(tenant.id, %{
          "company_name" => "Acme GmbH",
          "workflow_pain" => "Policy questions interrupt the ops lead a dozen times a week.",
          "systems" => "Slack, Notion, Gmail, HubSpot",
          "manual_steps" => "Look up the policy in Notion\nAsk the ops lead in Slack",
          "risk_notes" => "HR documents contain personal data",
          "success_metric" => "Ops-lead interruptions per week"
        })

      built = PlanBuilder.build(plan)

      labels = Enum.map(built.sources, & &1.label)
      assert Enum.any?(labels, &(&1 =~ "Slack channels"))
      assert Enum.any?(labels, &(&1 =~ "Docs exported as Markdown"))
      assert Enum.any?(labels, &(&1 =~ "Email"))
      assert Enum.any?(labels, &(&1 =~ "CRM"))

      email = Enum.find(built.sources, &(&1.label =~ "Email"))
      assert email.state == :planned

      assert built.first_automation.detail =~ "cited answers"
      assert built.first_automation.automation_candidate =~ "Look up the policy in Notion"

      assert Enum.any?(built.governance, &(&1 =~ "HR documents contain personal data"))
      assert Enum.any?(built.governance, &(&1 =~ "citation"))

      assert built.proof_metric.metric == "Ops-lead interruptions per week"
      assert [%{horizon: "First 30 days"} | _] = built.roadmap
      assert length(built.roadmap) == 3
    end

    test "provides sensible defaults for a minimal plan" do
      tenant = tenant_fixture("prospects-minimal")

      {:ok, plan} =
        Prospects.create_plan(tenant.id, %{
          "company_name" => "Tiny Co",
          "workflow_pain" => "Nobody knows where the current price list lives."
        })

      built = PlanBuilder.build(plan)

      assert length(built.sources) == 2
      assert built.proof_metric.metric =~ "Time from question"
      assert built.pain.manual_steps == []
    end
  end
end
