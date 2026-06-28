defmodule AndnativeAiWeb.UserLoginLiveTest do
  use AndnativeAiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import AndnativeAi.AccountsFixtures

  describe "login page" do
    test "renders the login form", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/login")

      assert has_element?(lv, "h1", "Sign in")
      assert has_element?(lv, "#login_form")
      assert has_element?(lv, "input[type=email]")
      assert has_element?(lv, "input[type=password]")
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

    test "returns the generic error for malformed params instead of raising", %{conn: conn} do
      conn = post(conn, ~p"/login", %{"user" => %{"email" => ["array"], "password" => "x"}})
      assert redirected_to(conn) == ~p"/login"
      refute get_session(conn, :user_token)

      conn = post(build_conn(), ~p"/login", %{"unexpected" => "shape"})
      assert redirected_to(conn) == ~p"/login"
    end
  end

  describe "session revocation (R4)" do
    test "a revoked session token is rejected on the next admin mount", %{conn: conn} do
      user = user_fixture()
      token = AndnativeAi.Accounts.generate_user_session_token(user)
      conn = conn |> init_test_session(%{}) |> put_session(:user_token, token)

      assert {:ok, _lv, _html} = live(conn, ~p"/admin/control-plane")

      AndnativeAi.Accounts.delete_user_session_token(token)
      assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/admin/control-plane")
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
    for path <- [
          "/admin/control-plane",
          "/admin/agents",
          "/admin/sources",
          "/admin/documents",
          "/admin/slack",
          "/admin/runtime"
        ] do
      test "GET #{path} redirects to /login", %{conn: conn} do
        assert {:error, {:redirect, %{to: "/login"}}} = live(conn, unquote(path))
      end
    end
  end
end
