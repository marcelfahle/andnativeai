defmodule AndnativeAiWeb.PageControllerTest do
  use AndnativeAiWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/admin/agents"
  end
end
