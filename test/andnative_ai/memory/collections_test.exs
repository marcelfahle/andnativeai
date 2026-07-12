defmodule AndnativeAi.Memory.CollectionsTest do
  use AndnativeAi.DataCase, async: true

  alias AndnativeAi.Memory
  alias AndnativeAi.Memory.Service
  alias AndnativeAi.Runtime.Audit
  alias AndnativeAi.Sources.CollectionClassifier

  defp tenant_fixture(slug) do
    {:ok, tenant} =
      Memory.create_tenant(%{name: String.upcase(slug), slug: slug, status: "active"})

    tenant
  end

  test "create_collection slugifies, validates kind, and records governance evidence" do
    tenant = tenant_fixture("collections-create")

    {:ok, collection} =
      Memory.create_collection(
        tenant.id,
        %{
          "name" => "Employee Handbook",
          "kind" => "handbook",
          "description" => "How we work, benefits, and titles at Acme."
        },
        actor: "marcel@example.com"
      )

    assert collection.slug == "employee-handbook"

    assert {:error, changeset} =
             Memory.create_collection(tenant.id, %{
               "name" => "Bad",
               "kind" => "nonsense",
               "description" => "A description long enough to pass."
             })

    assert %{kind: _} = errors_on(changeset)

    assert Enum.any?(
             Audit.list_recent_events(tenant.id, limit: 10),
             &(&1.event_kind == "collection_created" and &1.actor == "marcel@example.com")
           )
  end

  test "a deleted collection's name can be reused, and live conflicts land on :name" do
    tenant = tenant_fixture("collections-reuse")

    attrs = %{
      "name" => "37signals company handbook",
      "kind" => "handbook",
      "description" => "The 37signals handbook corpus for the demo."
    }

    {:ok, first} = Memory.create_collection(tenant.id, attrs)

    # While the first one is alive, the same name must conflict — visibly,
    # on the field the admin edits.
    assert {:error, changeset} = Memory.create_collection(tenant.id, attrs)
    assert %{name: ["is already used by another collection"]} = errors_on(changeset)

    {:ok, _} = Memory.soft_delete_collection(tenant.id, first.id)

    # After deletion the name is free again (delete → re-ingest demo flow).
    assert {:ok, second} = Memory.create_collection(tenant.id, attrs)
    assert second.slug == first.slug
    assert second.id != first.id
  end

  test "document citations are computed from the memory map even for stale file:// rows" do
    tenant = tenant_fixture("collections-stale-citation")

    {:ok, _} =
      Service.ingest(
        tenant.id,
        %{
          source_type: "document",
          source_id: "stale-1",
          name: "handbook.md",
          permalink_or_url: "file:///app/var/sources/1/handbook.md"
        },
        [
          %{
            text: "We work in six week cycles with cooldown in between.",
            provenance: %{"permalink" => "file:///app/var/sources/1/handbook.md"}
          }
        ],
        %{},
        "tenant",
        "default"
      )

    [result] = Service.search(tenant.id, "six week cycles", %{limit: 1})
    assert result.citation_url =~ "/admin/memory#memory-source-#{result.source.id}"
    refute result.citation_url =~ "file://"
  end

  test "collection context is embedded into chunks and scopes search" do
    tenant = tenant_fixture("collections-context")

    {:ok, handbook} =
      Memory.create_collection(tenant.id, %{
        "name" => "Employee handbook",
        "kind" => "handbook",
        "description" => "Company handbook for Acme."
      })

    {:ok, other} =
      Memory.create_collection(tenant.id, %{
        "name" => "Sales proposals",
        "kind" => "custom",
        "description" => "Customer proposals and pricing."
      })

    {:ok, _} =
      Service.ingest(
        tenant.id,
        %{
          source_type: "document",
          source_id: "hb-1",
          name: "benefits.md",
          permalink_or_url: "https://example.com/benefits",
          collection_id: handbook.id
        },
        ["[Employee handbook · benefits.md] Reimbursements above 500 need manager approval."],
        %{"permalink" => "https://example.com/benefits"},
        "tenant",
        "default"
      )

    {:ok, _} =
      Service.ingest(
        tenant.id,
        %{
          source_type: "document",
          source_id: "sp-1",
          name: "acme-proposal.md",
          permalink_or_url: "https://example.com/proposal",
          collection_id: other.id
        },
        ["[Sales proposals · acme-proposal.md] Reimbursement of travel is billed to the client."],
        %{"permalink" => "https://example.com/proposal"},
        "tenant",
        "default"
      )

    all = Service.search(tenant.id, "reimbursements manager approval", %{limit: 5})
    assert length(all) >= 1

    scoped =
      Service.search(tenant.id, "reimbursements", %{limit: 5, collection_id: handbook.id})

    assert Enum.all?(scoped, &(&1.source.collection_id == handbook.id))
    refute Enum.any?(scoped, &(&1.source.name == "acme-proposal.md"))
  end

  test "soft_delete_collection removes every member source from retrieval" do
    tenant = tenant_fixture("collections-delete")

    {:ok, collection} =
      Memory.create_collection(tenant.id, %{
        "name" => "Old policies",
        "kind" => "policies",
        "description" => "Superseded policies corpus."
      })

    {:ok, _} =
      Service.ingest(
        tenant.id,
        %{
          source_type: "document",
          source_id: "old-1",
          name: "old-policy.md",
          permalink_or_url: "https://example.com/old",
          collection_id: collection.id
        },
        ["The obsolete travel policy required fax approval."],
        %{"permalink" => "https://example.com/old"},
        "tenant",
        "default"
      )

    assert Service.search(tenant.id, "travel policy fax", %{limit: 5}) != []

    {:ok, %{deleted_sources_count: 1}} =
      Memory.soft_delete_collection(tenant.id, collection.id, actor: "marcel@example.com")

    assert Service.search(tenant.id, "travel policy fax", %{limit: 5}) == []
    assert Memory.list_collections(tenant.id) == []

    events = Audit.list_recent_events(tenant.id, limit: 10)
    assert Enum.any?(events, &(&1.event_kind == "collection_deleted"))
    assert Enum.any?(events, &(&1.event_kind == "source_deleted"))
  end

  describe "CollectionClassifier heuristics" do
    test "guesses handbook kind from filenames" do
      files = [
        %{filename: "Getting Started.md", preview: ""},
        %{filename: "Benefits and Perks.md", preview: ""},
        %{filename: "Moonlighting Handbook.md", preview: ""}
      ]

      proposal = CollectionClassifier.propose(files)
      assert proposal.kind == "handbook"
      assert proposal.name == "Company handbook"
      assert proposal.description =~ "3 documents"
    end

    test "prefers the suggested name from a folder or zip" do
      files = [%{filename: "roadmap.md", preview: ""}]
      proposal = CollectionClassifier.propose(files, "Acme Product Docs")
      assert proposal.name == "Acme Product Docs"
      assert proposal.kind == "product"
    end

    test "falls back to custom when nothing matches" do
      files = [%{filename: "misc.txt", preview: ""}]
      proposal = CollectionClassifier.propose(files)
      assert proposal.kind == "custom"
    end
  end
end
