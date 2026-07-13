defmodule AndnativeAi.Runtime.ModelPolicyTest do
  use AndnativeAi.DataCase, async: false

  alias AndnativeAi.Memory
  alias AndnativeAi.Memory.Agent
  alias AndnativeAi.Runtime.{Audit, ModelPolicy}

  defp tenant_fixture(slug) do
    {:ok, tenant} =
      Memory.create_tenant(%{name: String.upcase(slug), slug: slug, status: "active"})

    tenant
  end

  test "resolution order: capability override, then base model, then default" do
    agent = %Agent{model: "gpt-5.6-terra", model_policy: %{"write" => "claude-opus-4-8"}}

    assert ModelPolicy.resolve(agent, :write) == "claude-opus-4-8"
    assert ModelPolicy.resolve(agent, :chat) == "gpt-5.6-terra"

    bare = %Agent{model: nil, model_policy: %{}}
    assert ModelPolicy.resolve(bare, :chat) == ModelPolicy.default_model()
    assert ModelPolicy.resolve(nil, :classify) == ModelPolicy.default_model()
  end

  test "customer changeset cannot touch model or policy" do
    tenant = tenant_fixture("policy-cust")

    {:ok, agent} =
      Memory.create_agent(tenant.id, %{
        "name" => "Bran",
        "identity" => "Copilot.",
        "role" => "marketing",
        "status" => "active"
      })

    {:ok, updated} =
      Memory.update_agent(agent, %{
        "name" => "Bran",
        "model" => "sneaky-model",
        "model_policy" => %{"chat" => "sneaky-model"}
      })

    assert updated.model == nil
    assert updated.model_policy == %{}
  end

  test "model policy updates validate capabilities and record governance evidence" do
    tenant = tenant_fixture("policy-audit")

    {:ok, agent} =
      Memory.create_agent(tenant.id, %{
        "name" => "Bran",
        "identity" => "Copilot.",
        "role" => "marketing",
        "status" => "active"
      })

    assert {:error, changeset} =
             Memory.update_agent_model_policy(agent, %{
               "model_policy" => %{"paint" => "gpt-5.6-luna"}
             })

    assert %{model_policy: _} = errors_on(changeset)

    {:ok, updated} =
      Memory.update_agent_model_policy(
        agent,
        %{"model" => "gpt-5.6-terra", "model_policy" => %{"write" => "claude-opus-4-8"}},
        actor: "marcel@example.com"
      )

    assert updated.model_policy == %{"write" => "claude-opus-4-8"}

    event =
      tenant.id
      |> Audit.list_recent_events(limit: 10)
      |> Enum.find(&(&1.event_kind == "model_policy_changed"))

    assert event.actor == "marcel@example.com"
    assert event.metadata["model"] == "gpt-5.6-terra"
    assert event.metadata["overrides"] == %{"write" => "claude-opus-4-8"}
  end

  describe "provider_for/1" do
    test "claude models route to anthropic, everything else to openai" do
      assert ModelPolicy.provider_for("claude-opus-4-8") == :anthropic
      assert ModelPolicy.provider_for("claude-sonnet-5") == :anthropic
      assert ModelPolicy.provider_for("gpt-5.6-terra") == :openai
      assert ModelPolicy.provider_for("o4-mini") == :openai
      assert ModelPolicy.provider_for(nil) == :openai
    end
  end
end
