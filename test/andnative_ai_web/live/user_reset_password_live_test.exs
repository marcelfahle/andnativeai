defmodule AndnativeAiWeb.UserResetPasswordLiveTest do
  use AndnativeAiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions
  import AndnativeAi.AccountsFixtures

  alias AndnativeAi.Accounts

  describe "forgot password page" do
    test "renders the email form", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/reset-password")
      assert html =~ "Forgot your password"
    end

    test "sends a reset email for a known address and shows a generic message", %{conn: conn} do
      user = user_fixture()
      {:ok, lv, _html} = live(conn, ~p"/users/reset-password")

      {:ok, conn} =
        lv
        |> form("#forgot_password_form", user: %{email: user.email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/login")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "If your email is in our system"
      assert_email_sent()
    end

    test "shows the same message for an unknown email and sends nothing", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/reset-password")

      {:ok, conn} =
        lv
        |> form("#forgot_password_form", user: %{email: "nobody@example.com"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/login")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "If your email is in our system"
      refute_email_sent()
    end
  end

  describe "reset password page" do
    setup do
      user = user_fixture()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_reset_password_instructions(user, url)
        end)

      %{user: user, token: token}
    end

    test "resets the password with a valid token", %{conn: conn, user: user, token: token} do
      {:ok, lv, _html} = live(conn, ~p"/users/reset-password/#{token}")

      {:ok, conn} =
        lv
        |> form("#reset_password_form", user: %{password: "a freshly reset password"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/login")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "reset successfully"
      assert Accounts.get_user_by_email_and_password(user.email, "a freshly reset password")
      refute Accounts.get_user_by_reset_password_token(token)
    end

    test "invalidates the user's sessions after reset", %{conn: conn, user: user, token: token} do
      session = Accounts.generate_user_session_token(user)
      {:ok, lv, _html} = live(conn, ~p"/users/reset-password/#{token}")

      lv
      |> form("#reset_password_form", user: %{password: "a freshly reset password"})
      |> render_submit()

      refute Accounts.get_user_by_session_token(session)
    end

    test "rejects an invalid token", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login", flash: %{"error" => msg}}}} =
               live(conn, ~p"/users/reset-password/invalid-token")

      assert msg =~ "invalid or it has expired"
    end
  end
end
