defmodule AndnativeAiWeb.Admin.DocumentsLiveTest do
  use AndnativeAiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AndnativeAi.Memory.Service

  setup do
    raw_path =
      Path.join(System.tmp_dir!(), "andnative-live-docs-#{System.unique_integer([:positive])}")

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

  test "uploads a Markdown document from the admin UI", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/documents")

    assert has_element?(view, "#document-upload-form")
    assert has_element?(view, "#document-sources-empty")

    upload =
      file_input(view, "#document-upload-form", :document, [
        %{
          name: "handbook.md",
          content: "# Handbook\n\nRefund approval needs escalation.",
          type: "text/markdown",
          last_modified: 1_710_000_000
        }
      ])

    assert render_upload(upload, "handbook.md") =~ "100%"

    view
    |> form("#document-upload-form")
    |> render_submit()

    assert has_element?(view, "#document-sources [id^='source-']")

    tenant = AndnativeAi.Memory.ensure_demo_tenant!()
    [result | _] = Service.search(tenant.id, "refund escalation", %{limit: 2})
    assert result.source.name == "handbook.md"
  end
end
