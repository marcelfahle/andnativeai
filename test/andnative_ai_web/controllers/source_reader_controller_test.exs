defmodule AndnativeAiWeb.SourceReaderControllerTest do
  use AndnativeAiWeb.ConnCase, async: false

  alias AndnativeAi.Memory
  alias AndnativeAi.Sources.DocumentIngestion

  setup do
    raw_path =
      Path.join(System.tmp_dir!(), "andnative-reader-#{System.unique_integer([:positive])}")

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

  defp ingest_handbook!(markdown) do
    tenant = Memory.ensure_demo_tenant!()
    path = Path.join(System.tmp_dir!(), "reader-#{System.unique_integer([:positive])}.md")
    File.write!(path, markdown)
    on_exit(fn -> File.rm(path) end)

    {:ok, %{source: source}} =
      DocumentIngestion.ingest_upload(tenant.id, %{path: path, filename: "handbook.md"})

    {tenant, source}
  end

  test "requires a logged-in workspace member", %{conn: conn} do
    {_tenant, source} = ingest_handbook!("# Hi")

    conn = get(conn, ~p"/sources/#{source.id}")
    assert redirected_to(conn) == ~p"/login"
  end

  describe "authenticated" do
    setup :register_and_log_in_user

    test "renders the cited document as readable HTML", %{conn: conn} do
      {_tenant, source} =
        ingest_handbook!("# How we work\n\nWe work in **six week** cycles.")

      conn = get(conn, ~p"/sources/#{source.id}")
      html = html_response(conn, 200)

      assert html =~ "handbook.md"
      assert html =~ "<h1>How we work</h1>"
      assert html =~ "<strong>six week</strong>"
    end

    test "never renders raw HTML from uploaded documents", %{conn: conn} do
      {_tenant, source} =
        ingest_handbook!("# Doc\n\n<script>alert(1)</script>")

      conn = get(conn, ~p"/sources/#{source.id}")
      html = html_response(conn, 200)

      refute html =~ "<script>alert(1)</script>"
    end

    test "404s for deleted sources and garbage ids", %{conn: conn} do
      {tenant, source} = ingest_handbook!("# Gone")
      {:ok, _} = Memory.soft_delete_source(tenant.id, source.id)

      assert conn |> get(~p"/sources/#{source.id}") |> html_response(404)
      assert conn |> get("/sources/not-a-number") |> html_response(404)
      assert conn |> get("/sources/999999") |> html_response(404)
    end
  end
end
