defmodule AndnativeAi.Runtime.AuditTest do
  use AndnativeAi.DataCase, async: true

  alias AndnativeAi.Memory
  alias AndnativeAi.Runtime.Audit
  alias AndnativeAi.Runtime.{AuditEvent, AuditEventKinds}

  test "records and lists tenant-scoped audit events newest first" do
    tenant = tenant_fixture("audit")
    other_tenant = tenant_fixture("audit-other")
    old_time = ~U[2026-06-28 10:00:00Z]
    new_time = ~U[2026-06-28 10:01:00Z]

    assert {:ok, old_event} =
             Audit.record_event(%{
               tenant_id: tenant.id,
               event_kind: "source_ingested",
               component: "memory_service",
               actor: "Memory service",
               status: "ready",
               summary: "Old event",
               metadata: %{item_count: 1},
               occurred_at: old_time
             })

    assert {:ok, new_event} =
             Audit.record_event(%{
               tenant_id: tenant.id,
               event_kind: "memory_searched",
               component: "runtime",
               actor: "Demo Agent",
               status: "ok",
               summary: "New event",
               metadata: %{result_count: 2},
               occurred_at: new_time
             })

    assert {:ok, _other_event} =
             Audit.record_event(%{
               tenant_id: other_tenant.id,
               event_kind: "memory_searched",
               component: "runtime",
               actor: "Other",
               status: "ok",
               summary: "Other tenant event"
             })

    assert [listed_new_event, listed_old_event] = Audit.list_recent_events(tenant.id, limit: 5)
    assert listed_new_event.id == new_event.id
    assert listed_old_event.id == old_event.id
  end

  test "list_recent_events applies limit" do
    tenant = tenant_fixture("audit-limit")

    for index <- 1..3 do
      assert {:ok, _event} =
               Audit.record_event(%{
                 tenant_id: tenant.id,
                 event_kind: "memory_searched",
                 component: "runtime",
                 actor: "Runtime",
                 status: "ok",
                 summary: "Event #{index}",
                 occurred_at: DateTime.add(~U[2026-06-28 10:00:00Z], index, :second)
               })
    end

    assert [%{summary: "Event 3"}, %{summary: "Event 2"}] =
             Audit.list_recent_events(tenant.id, limit: 2)
  end

  test "supports optional agent, source, and memory item links" do
    tenant = tenant_fixture("audit-links")

    {:ok, agent} =
      Memory.create_agent(tenant.id, %{
        name: "Audit Agent",
        identity: "Answer from memory.",
        model: "gpt-4.1-mini",
        runtime: "openclaw",
        status: "active"
      })

    {:ok, source} =
      Memory.create_source(tenant.id, %{
        source_type: "document",
        source_id: "audit-doc",
        name: "audit.md",
        status: "ready"
      })

    {:ok, item} =
      Memory.create_memory_item(tenant.id, source, %{
        source_type: "document",
        text: "Audit rows should be linkable.",
        provenance: %{},
        visibility: "tenant",
        retention_class: "default"
      })

    assert {:ok, event} =
             Audit.record_event(%{
               tenant_id: tenant.id,
               agent_id: agent.id,
               source_id: source.id,
               memory_item_id: item.id,
               request_id: "req-123",
               event_kind: "citation_attached",
               component: "runtime",
               actor: agent.name,
               status: "cited",
               summary: "Citation attached",
               citation_url: "https://example.com/audit"
             })

    assert event.agent_id == agent.id
    assert event.source_id == source.id
    assert event.memory_item_id == item.id
    assert event.request_id == "req-123"
  end

  test "rejects invalid events" do
    tenant = tenant_fixture("audit-invalid")

    assert {:error, changeset} =
             Audit.record_event(%{
               tenant_id: tenant.id,
               event_kind: "unknown_kind",
               component: "runtime",
               actor: "Runtime",
               status: "ok",
               summary: "Invalid event"
             })

    assert %{event_kind: ["is invalid"]} = errors_on(changeset)
  end

  test "sanitizes metadata before storing" do
    tenant = tenant_fixture("audit-sanitize")
    long_value = String.duplicate("a", 350)

    assert {:ok, event} =
             Audit.record_event(%{
               tenant_id: tenant.id,
               event_kind: "slack_mention_received",
               component: "slack_listener",
               actor: "Slack listener",
               status: "received",
               summary: "Slack mention received",
               metadata: %{
                 bot_token: "xoxb-secret",
                 question: "what is in memory?",
                 channel_id: "C123",
                 nested: %{answer_body: "do not keep", team_id: "T123"},
                 answer: "do not keep either",
                 long_value: long_value
               }
             })

    refute Map.has_key?(event.metadata, "bot_token")
    refute Map.has_key?(event.metadata, "question")
    refute Map.has_key?(event.metadata, "answer")
    refute Map.has_key?(event.metadata["nested"], "answer_body")
    assert event.metadata["channel_id"] == "C123"
    assert event.metadata["nested"]["team_id"] == "T123"
    assert String.ends_with?(event.metadata["long_value"], "...")
  end

  test "redacts sensitive strings and structurally sanitizes reason summaries" do
    reason =
      Audit.reason_summary(%{
        bot_token: "xoxb-secret-token",
        answer: "full answer body",
        nested: %{text: "raw question", safe_code: :rate_limited},
        message: "authorization=Bearer sk-testsecret"
      })

    refute reason =~ "xoxb-secret-token"
    refute reason =~ "full answer body"
    refute reason =~ "raw question"
    refute reason =~ "sk-testsecret"
    assert reason =~ "rate_limited"
    assert reason =~ "[REDACTED]"
  end

  test "event kind registry covers every valid audit kind with display metadata" do
    assert Enum.sort(AuditEvent.event_kinds()) == Enum.sort(AuditEventKinds.keys())

    for kind <- AuditEvent.event_kinds() do
      display = AuditEventKinds.display(kind)
      assert is_binary(display.label)
      assert is_binary(display.icon)
      assert display.tone in [:ready, :warning, :error]
    end
  end

  test "accepts known string keys and ignores unknown string keys" do
    tenant = tenant_fixture("audit-string-keys")

    assert {:ok, event} =
             Audit.record_event(%{
               "tenant_id" => tenant.id,
               "event_kind" => "memory_searched",
               "component" => "runtime",
               "actor" => "Runtime",
               "status" => "ok",
               "summary" => "String-key event",
               "metadata" => %{"result_count" => 1},
               "unexpected_key" => "ignored"
             })

    assert event.tenant_id == tenant.id
    assert event.metadata["result_count"] == 1
  end

  describe "control-plane timeline queries" do
    test "list_events filters by category, query, and cursor" do
      tenant = tenant_fixture("audit-filters")

      {:ok, searched} =
        Audit.record_event(%{
          tenant_id: tenant.id,
          event_kind: "memory_searched",
          component: "memory_tool",
          actor: "Agent",
          status: "ok",
          summary: "Agent searched governed memory.",
          request_id: "req-a"
        })

      {:ok, deleted} =
        Audit.record_event(%{
          tenant_id: tenant.id,
          event_kind: "source_deleted",
          component: "memory_service",
          actor: "Memory service",
          status: "deleted",
          summary: "Handbook removed.",
          request_id: "req-b"
        })

      {:ok, indexed} =
        Audit.record_event(%{
          tenant_id: tenant.id,
          event_kind: "memory_indexed",
          component: "memory_service",
          actor: "Memory service",
          status: "indexed",
          summary: "Chunks indexed.",
          request_id: "req-c"
        })

      assert [%{id: id_a}] = Audit.list_events(tenant.id, category: "governance")
      assert id_a == deleted.id

      assert [%{id: ^id_a}] = Audit.list_events(tenant.id, category: :governance)

      assert [%{id: id_b}] = Audit.list_events(tenant.id, query: "req-a")
      assert id_b == searched.id

      assert [%{id: id_c}] = Audit.list_events(tenant.id, query: "handbook")
      assert id_c == deleted.id

      # Cursor pagination walks backwards through the (occurred_at, id)
      # ordering key.
      assert [first, second] = Audit.list_events(tenant.id, limit: 2)
      assert first.id == indexed.id

      assert [third] = Audit.list_events(tenant.id, before: second)
      assert third.id == searched.id
    end

    test "cursor pagination stays consistent with backdated occurred_at" do
      tenant = tenant_fixture("audit-backdated")
      base = ~U[2026-07-11 10:00:00Z]

      # Insert out of chronological order: the second insert is backdated,
      # so id order and occurred_at order disagree.
      for {offset, summary} <- [{2, "newest"}, {0, "oldest (backdated)"}, {1, "middle"}] do
        {:ok, _} =
          Audit.record_event(%{
            tenant_id: tenant.id,
            event_kind: "memory_indexed",
            component: "memory_service",
            actor: "Memory service",
            status: "indexed",
            summary: summary,
            occurred_at: DateTime.add(base, offset, :second)
          })
      end

      assert [page_one_first, page_one_second] = Audit.list_events(tenant.id, limit: 2)
      assert page_one_first.summary == "newest"
      assert page_one_second.summary == "middle"

      assert [last] = Audit.list_events(tenant.id, before: page_one_second, limit: 2)
      assert last.summary == "oldest (backdated)"
    end

    test "category_counts groups event totals by category" do
      tenant = tenant_fixture("audit-counts")

      for kind <- ["memory_searched", "memory_indexed", "source_deleted", "runtime_error"] do
        {:ok, _} =
          Audit.record_event(%{
            tenant_id: tenant.id,
            event_kind: kind,
            component: "memory_service",
            actor: "Memory service",
            status: "ok",
            summary: "#{kind} happened"
          })
      end

      counts = Audit.category_counts(tenant.id)

      assert counts[:all] == 4
      assert counts[:memory] == 1
      assert counts[:runtime] == 1
      assert counts[:governance] == 1
      assert counts[:errors] == 1

      assert Audit.count_events_by_kind(tenant.id, "memory_indexed") == 1
    end

    test "list_request_events returns the correlated trace oldest first" do
      tenant = tenant_fixture("audit-trace")

      {:ok, first} =
        Audit.record_event(%{
          tenant_id: tenant.id,
          event_kind: "slack_mention_received",
          component: "slack_listener",
          actor: "Slack listener",
          status: "received",
          summary: "Mention received.",
          request_id: "req-trace",
          occurred_at: ~U[2026-07-11 10:00:00Z]
        })

      {:ok, second} =
        Audit.record_event(%{
          tenant_id: tenant.id,
          event_kind: "answer_generated",
          component: "openclaw_runtime",
          actor: "Agent",
          status: "ok",
          summary: "Answer generated.",
          request_id: "req-trace",
          occurred_at: ~U[2026-07-11 10:00:01Z]
        })

      assert [%{id: id_1}, %{id: id_2}] = Audit.list_request_events(tenant.id, "req-trace")
      assert id_1 == first.id
      assert id_2 == second.id

      assert Audit.list_request_events(tenant.id, nil) == []
      assert Audit.list_request_events(tenant.id, "") == []
    end

    test "recorded events broadcast to tenant subscribers" do
      tenant = tenant_fixture("audit-pubsub")
      :ok = Audit.subscribe(tenant.id)

      {:ok, event} =
        Audit.record_event(%{
          tenant_id: tenant.id,
          event_kind: "memory_indexed",
          component: "memory_service",
          actor: "Memory service",
          status: "indexed",
          summary: "Broadcast me."
        })

      event_id = event.id
      assert_receive {:audit_event_recorded, %AuditEvent{id: ^event_id}}
    end
  end

  defp tenant_fixture(slug) do
    {:ok, tenant} =
      Memory.create_tenant(%{
        name: String.upcase(slug),
        slug: slug,
        status: "active"
      })

    tenant
  end
end
