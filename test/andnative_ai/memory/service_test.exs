defmodule AndnativeAi.Memory.ServiceTest do
  use AndnativeAi.DataCase, async: false

  alias AndnativeAi.Memory
  alias AndnativeAi.Memory.Service
  alias AndnativeAi.Runtime.Audit

  describe "ingest/search/delete" do
    test "ingests chunks and retrieves the right one by vector query" do
      tenant = tenant_fixture("semantic")

      assert {:ok, %{source: source, items: items}} =
               Service.ingest(
                 tenant.id,
                 %{
                   source_type: "document",
                   source_id: "demo-runbook",
                   name: "Demo runbook",
                   permalink_or_url: "https://docs.example.com/demo-runbook"
                 },
                 [
                   %{text: "The onboarding runbook says finance approvals require Clara."},
                   %{
                     text:
                       "Refund requests above 500 need support escalation and manager approval.",
                     provenance: %{"permalink" => "https://docs.example.com/demo-runbook#refunds"}
                   },
                   %{text: "The roadmap demo uses OpenClaw after Slack citations are attached."}
                 ],
                 %{"document" => "demo-runbook"},
                 "tenant",
                 "demo"
               )

      assert length(items) == 3
      assert source.status == "ready"

      [result | _] =
        Service.search(tenant.id, "How do we handle reimbursement approval?", %{limit: 3})

      assert result.text =~ "Refund requests"
      assert result.score > 0.0
      assert result.source.name == "Demo runbook"
      assert result.citation_url == "https://docs.example.com/demo-runbook#refunds"
      assert result.provenance["document"] == "demo-runbook"

      event_kinds =
        tenant.id
        |> Audit.list_recent_events(limit: 10)
        |> Enum.map(& &1.event_kind)

      assert "source_ingested" in event_kinds
      assert "memory_indexed" in event_kinds

      source_event =
        tenant.id
        |> Audit.list_recent_events(limit: 10)
        |> Enum.find(&(&1.event_kind == "source_ingested"))

      assert source_event.source_id == source.id
      assert source_event.metadata["item_count"] == 3
      assert source_event.citation_url == "https://docs.example.com/demo-runbook"
    end

    test "search only returns rows for the requested tenant" do
      tenant_a = tenant_fixture("search-a")
      tenant_b = tenant_fixture("search-b")

      {:ok, _} =
        Service.ingest(
          tenant_a.id,
          source_attrs("source-a"),
          ["Support escalation requires Ada."],
          %{},
          "tenant",
          "default"
        )

      {:ok, _} =
        Service.ingest(
          tenant_b.id,
          source_attrs("source-b"),
          ["Support escalation requires Grace."],
          %{},
          "tenant",
          "default"
        )

      assert [%{text: text_a}] = Service.search(tenant_a.id, "support escalation", %{limit: 5})
      assert text_a =~ "Ada"

      assert [%{text: text_b}] = Service.search(tenant_b.id, "support escalation", %{limit: 5})
      assert text_b =~ "Grace"
    end

    test "deleting a source removes it from future search results" do
      tenant = tenant_fixture("delete-search")

      {:ok, %{source: source}} =
        Service.ingest(
          tenant.id,
          source_attrs("delete-source"),
          ["The citation source should disappear after delete."],
          %{"permalink" => "https://example.com/delete-source"},
          "tenant",
          "default"
        )

      assert [_result] = Service.search(tenant.id, "citation source", %{limit: 5})

      assert {:ok, %{deleted_items_count: 1}} = Service.delete_source(tenant.id, source.id)

      assert [] = Service.search(tenant.id, "citation source", %{limit: 5})

      [delete_event] =
        tenant.id
        |> Audit.list_recent_events(limit: 10)
        |> Enum.filter(&(&1.event_kind == "source_deleted"))

      assert delete_event.source_id == source.id
      assert delete_event.metadata["deleted_items_count"] == 1
    end

    test "source operations survive audit recorder failure" do
      tenant = tenant_fixture("audit-reject")
      previous_recorder = Application.get_env(:andnative_ai, :audit_recorder)

      Application.put_env(:andnative_ai, :audit_recorder, fn _attrs ->
        {:error, :audit_unavailable}
      end)

      on_exit(fn ->
        if previous_recorder do
          Application.put_env(:andnative_ai, :audit_recorder, previous_recorder)
        else
          Application.delete_env(:andnative_ai, :audit_recorder)
        end
      end)

      assert {:ok, %{source: source, items: [_item]}} =
               Service.ingest(
                 tenant.id,
                 %{
                   source_type: "document",
                   source_id: "audit-reject-source",
                   name: "audit-reject-source.md",
                   permalink_or_url: "https://docs.example.com/audit-reject"
                 },
                 ["Audit failures must not block memory ingestion."],
                 %{},
                 "tenant",
                 "default"
               )

      assert source.status == "ready"
      assert [_result] = Service.search(tenant.id, "memory ingestion", %{limit: 5})

      assert {:ok, %{deleted_items_count: 1}} = Service.delete_source(tenant.id, source.id)
      assert [] = Service.search(tenant.id, "memory ingestion", %{limit: 5})
    end

    test "search does not return unrelated nearest-neighbor results" do
      tenant = tenant_fixture("unrelated-search")

      {:ok, _} =
        Service.ingest(
          tenant.id,
          source_attrs("launch-source"),
          ["The launch decision is owned by Ada and cites Slack."],
          %{},
          "tenant",
          "default"
        )

      assert [] = Service.search(tenant.id, "reimbursements manager approval", %{limit: 5})
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

  defp source_attrs(id) do
    %{
      source_type: "document",
      source_id: id,
      name: "#{id}.md",
      permalink_or_url: "https://docs.example.com/#{id}"
    }
  end
end
