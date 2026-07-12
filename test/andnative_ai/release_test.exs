defmodule AndnativeAi.ReleaseTest do
  use AndnativeAi.DataCase, async: false

  alias AndnativeAi.Memory
  alias AndnativeAi.Memory.Service
  alias AndnativeAi.Release

  test "reset_demo_memory clears demo tenant sources and items but keeps agents" do
    tenant = Memory.ensure_demo_tenant!()

    {:ok, agent} =
      Memory.create_agent(tenant.id, %{
        name: "Reset Survivor",
        identity: "Answer from governed memory.",
        model: "gpt-4.1-mini",
        runtime: "openclaw",
        status: "active"
      })

    {:ok, _} =
      Service.ingest(
        tenant.id,
        %{
          source_type: "document",
          source_id: "reset-me",
          name: "reset.md",
          permalink_or_url: "https://example.com/reset"
        },
        ["This memory should not survive the demo reset."],
        %{"permalink" => "https://example.com/reset"},
        "tenant",
        "default"
      )

    assert Memory.count_memory_items(tenant.id) > 0

    events_before = AndnativeAi.Runtime.Audit.list_recent_events(tenant.id, limit: 50)
    assert events_before != []

    assert :ok = Release.reset_demo_memory()

    assert Memory.count_memory_items(tenant.id) == 0
    assert Memory.list_all_sources(tenant.id) == []
    assert [%{id: agent_id}] = Memory.list_agents(tenant.id)
    assert agent_id == agent.id

    # Audit evidence survives the reset; source links are nilified.
    events_after = AndnativeAi.Runtime.Audit.list_recent_events(tenant.id, limit: 50)
    assert length(events_after) == length(events_before)
    assert Enum.all?(events_after, &is_nil(&1.source_id))
  end
end
