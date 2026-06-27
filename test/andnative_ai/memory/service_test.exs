defmodule AndnativeAi.Memory.ServiceTest do
  use AndnativeAi.DataCase, async: true

  alias AndnativeAi.Memory
  alias AndnativeAi.Memory.Service

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
