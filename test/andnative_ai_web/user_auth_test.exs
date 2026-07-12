defmodule AndnativeAiWeb.UserAuthTest do
  use AndnativeAiWeb.ConnCase, async: true

  import AndnativeAi.AccountsFixtures

  alias AndnativeAi.Accounts
  alias AndnativeAiWeb.UserAuth

  setup %{conn: conn} do
    conn =
      conn
      |> Map.replace!(:secret_key_base, AndnativeAiWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{})

    %{user: user_fixture(), conn: conn}
  end

  describe "log_in_user/3" do
    test "stores the user token in the session and redirects", %{conn: conn, user: user} do
      conn = UserAuth.log_in_user(conn, user)

      assert token = get_session(conn, :user_token)
      assert get_session(conn, :live_socket_id) == "users_sessions:#{Base.url_encode64(token)}"
      assert redirected_to(conn) == ~p"/admin/control-plane"
      assert Accounts.get_user_by_session_token(token).id == user.id
    end

    test "redirects to the stored return_to path", %{conn: conn, user: user} do
      conn =
        conn
        |> put_session(:user_return_to, "/admin/agents")
        |> UserAuth.log_in_user(user)

      assert redirected_to(conn) == "/admin/agents"
    end
  end

  describe "log_out_user/1" do
    test "clears the session and deletes the token", %{conn: conn, user: user} do
      token = Accounts.generate_user_session_token(user)

      conn =
        conn
        |> put_session(:user_token, token)
        |> UserAuth.log_out_user()

      refute get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/login"
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "fetch_current_user/2" do
    test "assigns the user when a valid token is present", %{conn: conn, user: user} do
      token = Accounts.generate_user_session_token(user)

      conn =
        conn
        |> put_session(:user_token, token)
        |> UserAuth.fetch_current_user([])

      assert conn.assigns.current_user.id == user.id
    end

    test "assigns nil when no token is present", %{conn: conn} do
      conn = UserAuth.fetch_current_user(conn, [])
      refute conn.assigns.current_user
    end
  end

  describe "require_authenticated_user/2" do
    test "redirects unauthenticated users to login and stores the return path" do
      conn =
        build_conn(:get, "/admin/agents")
        |> Map.replace!(:secret_key_base, AndnativeAiWeb.Endpoint.config(:secret_key_base))
        |> init_test_session(%{})
        |> Phoenix.Controller.fetch_flash()
        |> UserAuth.require_authenticated_user([])

      assert conn.halted
      assert redirected_to(conn) == ~p"/login"
      assert get_session(conn, :user_return_to) == "/admin/agents"
    end

    test "does not redirect an authenticated user", %{conn: conn, user: user} do
      conn = conn |> assign(:current_user, user) |> UserAuth.require_authenticated_user([])
      refute conn.halted
      refute conn.status
    end
  end

  describe "on_mount :mount_current_user" do
    test "assigns the current user when the session has a valid token", %{user: user} do
      token = Accounts.generate_user_session_token(user)
      session = %{"user_token" => token}

      assert {:cont, socket} =
               UserAuth.on_mount(:mount_current_user, %{}, session, %Phoenix.LiveView.Socket{})

      assert socket.assigns.current_user.id == user.id
    end

    test "assigns nil when the session has no token" do
      assert {:cont, socket} =
               UserAuth.on_mount(:mount_current_user, %{}, %{}, %Phoenix.LiveView.Socket{})

      assert is_nil(socket.assigns.current_user)
    end
  end

  describe "on_mount :require_authenticated" do
    test "continues with the current user when the session token is valid", %{user: user} do
      token = Accounts.generate_user_session_token(user)
      session = %{"user_token" => token}

      assert {:cont, socket} =
               UserAuth.on_mount(:require_authenticated, %{}, session, %Phoenix.LiveView.Socket{})

      assert socket.assigns.current_user.id == user.id
    end

    test "halts and redirects to /login when there is no valid token" do
      socket = %Phoenix.LiveView.Socket{
        endpoint: AndnativeAiWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      assert {:halt, halted} = UserAuth.on_mount(:require_authenticated, %{}, %{}, socket)
      assert {:redirect, %{to: "/login"}} = halted.redirected
    end
  end

  describe "on_mount :require_superadmin" do
    test "continues for a superadmin", %{user: user} do
      {:ok, superadmin} = Accounts.set_user_role(user, "superadmin")
      token = Accounts.generate_user_session_token(superadmin)
      session = %{"user_token" => token}

      assert {:cont, socket} =
               UserAuth.on_mount(:require_superadmin, %{}, session, %Phoenix.LiveView.Socket{})

      assert socket.assigns.current_user.role == "superadmin"
    end

    test "halts and redirects an ordinary admin away", %{user: user} do
      token = Accounts.generate_user_session_token(user)
      session = %{"user_token" => token}

      socket = %Phoenix.LiveView.Socket{
        endpoint: AndnativeAiWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      assert {:halt, halted} = UserAuth.on_mount(:require_superadmin, %{}, session, socket)
      assert {:redirect, %{to: "/admin/control-plane"}} = halted.redirected
    end

    test "halts and redirects to /login when unauthenticated" do
      socket = %Phoenix.LiveView.Socket{
        endpoint: AndnativeAiWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      assert {:halt, halted} = UserAuth.on_mount(:require_superadmin, %{}, %{}, socket)
      assert {:redirect, %{to: "/login"}} = halted.redirected
    end
  end

  describe "require_superadmin_user/2" do
    test "passes a superadmin through", %{conn: conn, user: user} do
      {:ok, superadmin} = Accounts.set_user_role(user, "superadmin")

      conn =
        conn
        |> assign(:current_user, superadmin)
        |> Phoenix.Controller.fetch_flash()
        |> UserAuth.require_superadmin_user([])

      refute conn.halted
    end

    test "halts and redirects an ordinary admin", %{conn: conn, user: user} do
      conn =
        conn
        |> assign(:current_user, user)
        |> Phoenix.Controller.fetch_flash()
        |> UserAuth.require_superadmin_user([])

      assert conn.halted
      assert redirected_to(conn) == ~p"/admin/control-plane"
    end

    test "halts and redirects when unauthenticated", %{conn: conn} do
      conn =
        conn
        |> Phoenix.Controller.fetch_flash()
        |> UserAuth.require_superadmin_user([])

      assert conn.halted
    end
  end
end
