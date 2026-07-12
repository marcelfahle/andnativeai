defmodule AndnativeAiWeb.Admin.CollectionFlowTest do
  use AndnativeAiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AndnativeAi.Memory
  alias AndnativeAi.Memory.Service
  alias AndnativeAi.Sources.DocumentIngestion

  setup :register_and_log_in_user

  setup do
    raw_path =
      Path.join(System.tmp_dir!(), "andnative-collections-#{System.unique_integer([:positive])}")

    previous_path = Application.get_env(:andnative_ai, :raw_sources_path)
    Application.put_env(:andnative_ai, :raw_sources_path, raw_path)

    on_exit(fn ->
      if previous_path do
        Application.put_env(:andnative_ai, :raw_sources_path, previous_path)
      else
        Application.delete_env(:andnative_ai, :raw_sources_path)
      end

      File.rm_rf(raw_path)
    end)

    :ok
  end

  test "multi-file upload stages, proposes, confirms, and ingests a collection", %{conn: conn} do
    tenant = Memory.ensure_demo_tenant!()

    {:ok, view, _html} = live(conn, ~p"/admin/sources")

    # Each file auto-uploads and stages on completion (auto_upload +
    # progress); one file_input per file mirrors files arriving one by one.
    view
    |> file_input("#collection-upload-form", :collection_docs, [
      %{
        name: "Benefits and Perks.md",
        content: "# Benefits\n\nReimbursements above 500 EUR require manager approval.",
        type: "text/markdown"
      }
    ])
    |> render_upload("Benefits and Perks.md")

    view
    |> file_input("#collection-upload-form", :collection_docs, [
      %{
        name: "Getting Started.md",
        content: "# Getting Started\n\nYour onboarding buddy helps in week one.",
        type: "text/markdown"
      }
    ])
    |> render_upload("Getting Started.md")

    assert has_element?(view, "#collection-staged-count", "2 documents staged")

    view |> form("#collection-upload-form") |> render_submit()

    # The classifier proposes a handbook collection; the admin confirms.
    assert has_element?(view, "#collection-proposal")
    assert has_element?(view, "#collection-confirm-form")

    view
    |> form("#collection-confirm-form", %{
      collection: %{
        name: "Employee handbook",
        kind: "handbook",
        description: "The Acme employee handbook: benefits, onboarding, policies."
      }
    })
    |> render_submit()

    assert [collection] = Memory.list_collections(tenant.id)
    assert collection.name == "Employee handbook"
    assert has_element?(view, "#collection-#{collection.id}", "Employee handbook")

    # Both documents were ingested into the collection with context prefixes.
    results = Service.search(tenant.id, "reimbursements manager approval", %{limit: 5})
    assert Enum.any?(results, &(&1.source.collection_id == collection.id))
    assert Enum.any?(results, &String.contains?(&1.text, "[Employee handbook · Benefits"))

    # The memory map groups the collection.
    {:ok, map_view, _html} = live(conn, ~p"/admin/memory")
    assert has_element?(map_view, "#memory-collection-#{collection.id}", "Employee handbook")

    # Deleting the collection removes its documents from retrieval.
    view
    |> element("#delete-collection-#{collection.id}")
    |> render_click()

    assert Service.search(tenant.id, "reimbursements manager approval", %{limit: 5}) == []
  end

  test "discard clears staged files without creating anything", %{conn: conn} do
    tenant = Memory.ensure_demo_tenant!()

    {:ok, view, _html} = live(conn, ~p"/admin/sources")

    view
    |> file_input("#collection-upload-form", :collection_docs, [
      %{name: "notes.md", content: "# Meeting notes\n\nWe met.", type: "text/markdown"}
    ])
    |> render_upload("notes.md")

    view |> form("#collection-upload-form") |> render_submit()

    assert has_element?(view, "#collection-proposal")

    view |> element("#collection-discard") |> render_click()

    refute has_element?(view, "#collection-proposal")
    assert Memory.list_collections(tenant.id) == []
  end

  test "stage_upload expands zip archives safely" do
    staging_dir =
      Path.join(System.tmp_dir!(), "andnative-zip-test-#{System.unique_integer([:positive])}")

    zip_dir =
      Path.join(System.tmp_dir!(), "andnative-zip-src-#{System.unique_integer([:positive])}")

    File.mkdir_p!(zip_dir)
    File.write!(Path.join(zip_dir, "handbook.md"), "# Handbook\n\nApprovals need a manager.")
    File.write!(Path.join(zip_dir, "image.png"), <<137, 80, 78, 71>>)

    zip_path =
      Path.join(System.tmp_dir!(), "andnative-test-#{System.unique_integer([:positive])}.zip")

    {:ok, _} =
      :zip.create(
        String.to_charlist(zip_path),
        [
          String.to_charlist(Path.join(zip_dir, "handbook.md")),
          String.to_charlist(Path.join(zip_dir, "image.png"))
        ],
        cwd: String.to_charlist(zip_dir)
      )

    on_exit(fn ->
      File.rm_rf(staging_dir)
      File.rm_rf(zip_dir)
      File.rm(zip_path)
    end)

    {:ok, staged} =
      DocumentIngestion.stage_upload(staging_dir, %{
        path: zip_path,
        filename: "company-handbook.zip"
      })

    assert [%{filename: "handbook.md", preview: preview}] = staged
    assert preview =~ "Approvals need a manager"
  end
end
