defmodule AndnativeAiWeb.Admin.UsersLiveTest do
  use AndnativeAiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import AndnativeAi.AccountsFixtures
  import Swoosh.TestAssertions

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

    lv
    |> element("a[phx-click='resend'][phx-value-id='#{pending.id}']")
    |> render_click()

    assert has_element?(lv, "#flash-group", "Invitation resent")
    # The old invite token was rotated out.
    refute Accounts.get_user_by_invite_token(token)
  end

  test "ignores a crafted delete event targeting the current user", %{conn: conn, user: admin} do
    {:ok, lv, _html} = live(conn, ~p"/admin/users")

    # A crafted event sending the id as an integer (not the usual string) must
    # still be refused by the server-side self-delete guard.
    render_click(lv, "delete", %{"id" => admin.id})

    assert has_element?(lv, "#flash-group", "can't delete your own account")
    assert Accounts.get_user_by_email(admin.email)
  end

  describe "platform superadmin invisibility (AAI-34)" do
    setup :register_and_log_in_user

    test "superadmin rows never render and events targeting them are no-ops", %{conn: conn} do
      {:ok, superadmin} =
        AndnativeAi.Accounts.set_user_role(
          user_fixture(%{email: "platform@andnative.ai"}),
          "superadmin"
        )

      {:ok, view, html} = live(conn, ~p"/admin/users")

      refute html =~ "platform@andnative.ai"

      # Crafted events against the hidden account must be no-ops — and answer
      # exactly like a missing user, so nothing is enumerable.
      render_click(view, "delete", %{"id" => to_string(superadmin.id)})
      assert AndnativeAi.Accounts.get_user(superadmin.id)

      html = render_click(view, "resend", %{"id" => to_string(superadmin.id)})
      assert html =~ "That user no longer exists."
      assert_no_email_sent()
    end

    test "a superadmin sees platform accounts and can act on them", %{conn: conn, user: user} do
      {:ok, viewer} = AndnativeAi.Accounts.set_user_role(user, "superadmin")
      conn = log_in_user(conn, viewer)

      {:ok, _other} =
        AndnativeAi.Accounts.set_user_role(
          user_fixture(%{email: "platform2@andnative.ai"}),
          "superadmin"
        )

      {:ok, _view, html} = live(conn, ~p"/admin/users")

      # Staff hiding from staff serves no one — the page must not look empty.
      assert html =~ "platform2@andnative.ai"
      assert html =~ viewer.email
    end

    test "inviting a platform email never reveals the hidden account", %{conn: conn} do
      {:ok, superadmin} =
        AndnativeAi.Accounts.set_user_role(
          user_fixture(%{email: "hidden@andnative.ai"}),
          "superadmin"
        )

      # Same shape as a fresh invite (no unique-constraint error to read),
      # and nothing is delivered.
      # A customer admin gets the same shape as a fresh invite, and nothing
      # is delivered.
      customer_admin = user_fixture()

      assert {:ok, returned} =
               AndnativeAi.Accounts.invite_user("hidden@andnative.ai", &"http://x/#{&1}",
                 actor: customer_admin
               )

      assert returned.id == superadmin.id
      assert_no_email_sent()

      # Platform staff see the truth instead of a fiction.
      assert {:error, :already_active_superadmin} =
               AndnativeAi.Accounts.invite_user("hidden@andnative.ai", &"http://x/#{&1}",
                 actor: superadmin
               )
    end
  end
end
