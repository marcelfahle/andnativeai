defmodule AndnativeAiWeb.Admin.UsersLiveTest do
  use AndnativeAiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import AndnativeAi.AccountsFixtures

  alias AndnativeAi.Accounts

  setup :register_and_log_in_user

  defp invite(email) do
    extract_user_token(fn url -> {:ok, _user} = Accounts.invite_user(email, url) end)
  end

  test "redirects unauthenticated users to login" do
    assert {:error, {:redirect, %{to: "/login"}}} = live(build_conn(), ~p"/admin/users")
  end

  test "lists active and invited users with their status", %{conn: conn, user: admin} do
    invite("pending@example.com")

    {:ok, lv, _html} = live(conn, ~p"/admin/users")

    assert has_element?(lv, "#users", admin.email)
    assert has_element?(lv, "#users", "pending@example.com")
    assert has_element?(lv, "#users", "Active")
    assert has_element?(lv, "#users", "Invited")
  end

  test "offers no delete action for the current user's own row", %{conn: conn, user: admin} do
    {:ok, lv, _html} = live(conn, ~p"/admin/users")
    refute has_element?(lv, "a[phx-click='delete'][phx-value-id='#{admin.id}']")
  end

  test "deletes another user", %{conn: conn} do
    other = user_fixture()
    {:ok, lv, _html} = live(conn, ~p"/admin/users")

    assert has_element?(lv, "#users", other.email)

    lv
    |> element("a[phx-click='delete'][phx-value-id='#{other.id}']")
    |> render_click()

    refute has_element?(lv, "#users", other.email)
    refute Accounts.get_user_by_email(other.email)
  end

  test "resends an invitation to a pending user", %{conn: conn, user: admin} do
    token = invite("pending@example.com")
    pending = Accounts.get_user_by_invite_token(token)

    {:ok, lv, _html} = live(conn, ~p"/admin/users")

    # The current (active) admin has no resend action; the pending user does.
    refute has_element?(lv, "a[phx-click='resend'][phx-value-id='#{admin.id}']")

    html =
      lv
      |> element("a[phx-click='resend'][phx-value-id='#{pending.id}']")
      |> render_click()

    assert html =~ "Invitation resent"
    # The old invite token was rotated out.
    refute Accounts.get_user_by_invite_token(token)
  end
end
