defmodule AndnativeAi.Sources.DocumentIngestionTest do
  use AndnativeAi.DataCase, async: false

  alias AndnativeAi.Memory
  alias AndnativeAi.Memory.Service
  alias AndnativeAi.Runtime.Audit
  alias AndnativeAi.Sources.DocumentIngestion

  setup do
    raw_path =
      Path.join(System.tmp_dir!(), "andnative-docs-#{System.unique_integer([:positive])}")

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

  test "stores, chunks, ingests, searches, and deletes an uploaded Markdown document" do
    tenant = Memory.ensure_demo_tenant!()

    path =
      write_tmp_file(
        "handbook.md",
        "# Handbook\n\nRefund approvals require support escalation.\n\n## Launch\n\nDemo citations must include the source filename."
      )

    assert {:ok, %{source: source, items: items, stored_path: stored_path}} =
             DocumentIngestion.ingest_upload(tenant.id, %{path: path, filename: "handbook.md"})

    assert File.exists?(stored_path)
    assert source.name == "handbook.md"
    assert length(items) == 2

    assert Enum.any?(
             Audit.list_recent_events(tenant.id, limit: 10),
             &(&1.event_kind == "source_ingested" and &1.source_id == source.id)
           )

    [result | _] = Service.search(tenant.id, "reimbursement approval", %{limit: 2})
    assert result.text =~ "Refund approvals"
    assert result.source.name == "handbook.md"
    assert result.citation_url =~ "handbook.md"

    assert {:ok, %{deleted_items_count: 2}} =
             DocumentIngestion.delete_source(tenant.id, source.id)

    assert [] = Service.search(tenant.id, "reimbursement approval", %{limit: 2})
  end

  test "rejects non-text document types" do
    tenant = Memory.ensure_demo_tenant!()
    path = write_tmp_file("handbook.pdf", "not parsed")

    assert {:error, :unsupported_file_type} =
             DocumentIngestion.ingest_upload(tenant.id, %{path: path, filename: "handbook.pdf"})
  end

  defp write_tmp_file(filename, contents) do
    path = Path.join(System.tmp_dir!(), "#{System.unique_integer([:positive])}-#{filename}")
    File.write!(path, contents)
    path
  end
end
