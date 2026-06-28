defmodule AndnativeAiWeb.UserLoginLiveTest do
  use AndnativeAiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import AndnativeAi.AccountsFixtures

  describe "login page" do
    test "renders the login form", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/login")

      assert html =~ "Sign in"
      assert html =~ "Email"
      assert html =~ "Password"
    end

    test "redirects authenticated users away from the login page", %{conn: conn} do
      conn = log_in_user(conn, user_fixture())
      assert {:error, {:redirect, %{to: "/admin/control-plane"}}} = live(conn, ~p"/login")
    end
  end

  describe "POST /login" do
    test "logs the user in and reaches the admin UI", %{conn: conn} do
      user = user_fixture()

      conn =
        post(conn, ~p"/login", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/admin/control-plane"

      conn = get(conn, ~p"/admin/control-plane")
      assert html_response(conn, 200)
    end

    test "redirects to the originally requested admin page after login", %{conn: conn} do
      user = user_fixture()

      conn = get(conn, ~p"/admin/agents")
      assert redirected_to(conn) == ~p"/login"

      conn =
        post(conn, ~p"/login", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert redirected_to(conn) == ~p"/admin/agents"
    end

    test "shows a generic error and does not log in on a wrong password", %{conn: conn} do
      user = user_fixture()

      conn =
        post(conn, ~p"/login", %{
          "user" => %{"email" => user.email, "password" => "wrong wrong wrong"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
      assert redirected_to(conn) == ~p"/login"
      refute get_session(conn, :user_token)
    end

    test "shows the same generic error for an unknown email (no enumeration)", %{conn: conn} do
      conn =
        post(conn, ~p"/login", %{
          "user" => %{"email" => "nobody@example.com", "password" => valid_user_password()}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
      assert redirected_to(conn) == ~p"/login"
    end
  end

  describe "DELETE /logout" do
    test "logs the user out and blocks admin access again", %{conn: conn} do
      conn = log_in_user(conn, user_fixture())

      conn = delete(conn, ~p"/logout")
      assert redirected_to(conn) == ~p"/login"
      refute get_session(conn, :user_token)

      conn = get(conn, ~p"/admin/control-plane")
      assert redirected_to(conn) == ~p"/login"
    end
  end

  describe "unauthenticated admin access redirects to login (R1)" do
    for path <- ["/admin/control-plane", "/admin/agents", "/admin/sources", "/admin/slack"] do
      test "GET #{path} redirects to /login", %{conn: conn} do
        assert {:error, {:redirect, %{to: "/login"}}} = live(conn, unquote(path))
      end
    end
  end
end
