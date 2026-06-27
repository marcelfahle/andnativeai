defmodule AndnativeAi.MemoryTest do
  use AndnativeAi.DataCase, async: true

  alias AndnativeAi.Memory
  alias AndnativeAi.Memory.Item

  describe "core memory schema" do
    test "creates tenant-scoped agents, sources, and memory items" do
      tenant = tenant_fixture("acme")

      assert {:ok, agent} =
               Memory.create_agent(tenant.id, %{
                 name: "Ops Copilot",
                 identity: "Answers from governed company memory.",
                 model: "gpt-4.1-mini",
                 runtime: "openclaw",
                 status: "active"
               })

      assert agent.tenant_id == tenant.id

      source = source_fixture(tenant, "doc-1")

      assert {:ok, item} =
               Memory.create_memory_item(tenant.id, source, %{
                 text: "The launch checklist lives in the demo folder.",
                 provenance: %{
                   "slack_channel" => "C123",
                   "slack_ts" => "1710000000.000100",
                   "author" => "U123",
                   "permalink" => "https://example.slack.com/archives/C123/p1710000000000100"
                 }
               })

      assert item.tenant_id == tenant.id
      assert item.source_id == source.id
      assert item.provenance["permalink"] =~ "slack.com"
    end

    test "memory item changesets require tenant and source" do
      changeset = Item.changeset(%Item{}, %{text: "orphaned memory"})

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).tenant_id
      assert "can't be blank" in errors_on(changeset).source_id
    end

    test "memory queries are tenant-scoped by default" do
      tenant_a = tenant_fixture("tenant-a")
      tenant_b = tenant_fixture("tenant-b")
      source_a = source_fixture(tenant_a, "doc-a")
      source_b = source_fixture(tenant_b, "doc-b")

      {:ok, item_a} =
        Memory.create_memory_item(tenant_a.id, source_a, %{
          text: "Tenant A memory",
          provenance: %{"permalink" => "https://example.com/a"}
        })

      {:ok, item_b} =
        Memory.create_memory_item(tenant_b.id, source_b, %{
          text: "Tenant B memory",
          provenance: %{"permalink" => "https://example.com/b"}
        })

      assert Memory.list_memory_items(tenant_a.id) == [item_a]
      assert Memory.list_memory_items(tenant_b.id) == [item_b]
    end

    test "soft-deleting a source soft-deletes related memory items" do
      tenant = tenant_fixture("delete-test")
      source = source_fixture(tenant, "doc-delete")

      {:ok, _item} =
        Memory.create_memory_item(tenant.id, source, %{
          text: "Delete with source",
          provenance: %{"url" => "https://example.com/delete"}
        })

      assert {:ok, %{source: deleted_source, deleted_items_count: 1}} =
               Memory.soft_delete_source(tenant.id, source.id)

      assert deleted_source.deleted_at
      assert Memory.list_memory_items(tenant.id) == []

      assert [%{deleted_at: deleted_at}] =
               Memory.list_all_source_memory_items(tenant.id, source.id)

      assert deleted_at
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

  defp source_fixture(tenant, source_id) do
    {:ok, source} =
      Memory.create_source(tenant.id, %{
        source_type: "document",
        source_id: source_id,
        name: "#{source_id}.md",
        permalink_or_url: "file://#{source_id}.md",
        status: "ready"
      })

    source
  end
end
