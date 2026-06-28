defmodule AndnativeAiWeb.Admin.UserInviteLiveTest do
  use AndnativeAiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions
  import AndnativeAi.AccountsFixtures

  alias AndnativeAi.Accounts

  describe "invite page (admin)" do
    test "redirects unauthenticated users to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/admin/users/invite")
    end

    test "sends an invitation for a new email", %{conn: conn} do
      conn = log_in_user(conn, user_fixture())
      {:ok, lv, _html} = live(conn, ~p"/admin/users/invite")
      email = unique_user_email()

      lv
      |> form("#invite_form", user: %{email: email})
      |> render_submit()

      assert has_element?(lv, "#flash-group", "Invitation sent")
      assert_email_sent()
      assert Accounts.get_user_by_email(email)
    end

    test "shows an error when inviting an existing email", %{conn: conn} do
      conn = log_in_user(conn, user_fixture())
      existing = user_fixture()
      {:ok, lv, _html} = live(conn, ~p"/admin/users/invite")

      lv
      |> form("#invite_form", user: %{email: existing.email})
      |> render_submit()

      assert has_element?(lv, "#invite_form", "has already been taken")
    end
  end

  describe "accept invitation page (public)" do
    setup do
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          {:ok, _user} = Accounts.invite_user(email, url)
        end)

      %{email: email, token: token}
    end

    test "activates the account with a valid token", %{conn: conn, email: email, token: token} do
      {:ok, lv, _html} = live(conn, ~p"/users/invite/#{token}")

      {:ok, conn} =
        lv
        |> form("#accept_invitation_form", user: %{password: "the new account password"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/login")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "activated"
      assert Accounts.get_user_by_email_and_password(email, "the new account password")
      refute Accounts.get_user_by_invite_token(token)
    end

    test "rejects an invalid token", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login", flash: %{"error" => msg}}}} =
               live(conn, ~p"/users/invite/invalid-token")

      assert msg =~ "invalid or it has expired"
    end
  end
end
