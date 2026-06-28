defmodule AndnativeAiWeb.UserSettingsLiveTest do
  use AndnativeAiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import AndnativeAi.AccountsFixtures

  alias AndnativeAi.Accounts

  describe "settings page" do
    test "renders the change-password form for a logged-in user", %{conn: conn} do
      {:ok, _lv, html} = conn |> log_in_user(user_fixture()) |> live(~p"/users/settings")
      assert html =~ "Account settings"
      assert html =~ "New password"
    end

    test "redirects unauthenticated users to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/users/settings")
    end
  end

  describe "change password" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "changes the password with the correct current password", %{conn: conn, user: user} do
      new_password = "a new valid password"
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      lv
      |> form("#password_form", %{
        "current_password" => valid_user_password(),
        "user" => %{"email" => user.email, "password" => new_password}
      })
      |> render_submit()

      assert Accounts.get_user_by_email_and_password(user.email, new_password)
    end

    test "shows an error for a wrong current password", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#password_form", %{
          "current_password" => "wrong wrong wrong",
          "user" => %{"email" => user.email, "password" => "another valid password"}
        })
        |> render_submit()

      assert result =~ "is not valid"
      refute Accounts.get_user_by_email_and_password(user.email, "another valid password")
    end
  end
end
