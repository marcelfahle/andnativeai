defmodule AndnativeAiWeb.UserAuth do
  @moduledoc """
  Plugs and LiveView `on_mount` hooks for app-level admin authentication.

  The auth boundary is enforced in two places so it holds for both the initial
  dead render and the LiveView socket (including reconnects):

    * `require_authenticated_user/2` guards plug pipelines.
    * `on_mount(:require_authenticated, ...)` guards `live_session` mounts.
  """

  use AndnativeAiWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias AndnativeAi.Accounts

  @doc """
  Logs the user in.

  Renews the session ID to avoid fixation attacks, persists a session token,
  and redirects to the path the user originally requested (if any) or the
  default signed-in path.
  """
  def log_in_user(conn, user) do
    token = Accounts.generate_user_session_token(user)
    user_return_to = get_session(conn, :user_return_to)

    conn
    |> renew_session()
    |> put_token_in_session(token)
    |> redirect(to: user_return_to || signed_in_path(conn))
  end

  @doc """
  Logs the user out by deleting the session token, disconnecting any live
  sockets bound to this session, and clearing the session.
  """
  def log_out_user(conn) do
    user_token = get_session(conn, :user_token)
    user_token && Accounts.delete_user_session_token(user_token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      AndnativeAiWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session()
    |> redirect(to: ~p"/login")
  end

  @doc """
  Authenticates the user by looking up the session token and assigning
  `:current_user` (which may be `nil`).
  """
  def fetch_current_user(conn, _opts) do
    user_token = get_session(conn, :user_token)
    user = user_token && Accounts.get_user_by_session_token(user_token)
    assign(conn, :current_user, user)
  end

  @doc """
  Used for routes that require the user to be authenticated.
  """
  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> maybe_store_return_to()
      |> redirect(to: ~p"/login")
      |> halt()
    end
  end

  @doc """
  Used for routes that only platform staff may reach. Assumes
  `require_authenticated_user` ran earlier in the pipeline.
  """
  def require_superadmin_user(conn, _opts) do
    if AndnativeAi.Accounts.User.superadmin?(conn.assigns[:current_user]) do
      conn
    else
      conn
      |> put_flash(:error, "You do not have access to that page.")
      |> redirect(to: signed_in_path(conn))
      |> halt()
    end
  end

  @doc """
  Handles mounting the current user into LiveViews.

    * `:mount_current_user` - assigns `current_user` from the session.
    * `:require_authenticated` - assigns `current_user` and redirects to the
      login page when no authenticated user is present. Re-runs on every
      socket connect/reconnect, so auth survives reconnects.
    * `:require_superadmin` - like `:require_authenticated`, but also sends
      non-superadmins back to the control plane. Platform-staff surfaces
      (fleet operations, model policy) mount through this.
    * `:redirect_if_user_is_authenticated` - redirects already-authenticated
      users away from the login page.
  """
  def on_mount(:mount_current_user, _params, session, socket) do
    {:cont, mount_current_user(socket, session)}
  end

  def on_mount(:require_authenticated, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if socket.assigns.current_user do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "You must log in to access this page.")
        |> Phoenix.LiveView.redirect(to: ~p"/login")

      {:halt, socket}
    end
  end

  def on_mount(:require_superadmin, params, session, socket) do
    case on_mount(:require_authenticated, params, session, socket) do
      {:cont, socket} ->
        if AndnativeAi.Accounts.User.superadmin?(socket.assigns.current_user) do
          {:cont, socket}
        else
          socket =
            socket
            |> Phoenix.LiveView.put_flash(:error, "You do not have access to that page.")
            |> Phoenix.LiveView.redirect(to: signed_in_path(socket))

          {:halt, socket}
        end

      halted ->
        halted
    end
  end

  def on_mount(:redirect_if_user_is_authenticated, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if socket.assigns.current_user do
      {:halt, Phoenix.LiveView.redirect(socket, to: signed_in_path(socket))}
    else
      {:cont, socket}
    end
  end

  defp mount_current_user(socket, session) do
    Phoenix.Component.assign_new(socket, :current_user, fn ->
      if user_token = session["user_token"] do
        Accounts.get_user_by_session_token(user_token)
      end
    end)
  end

  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  defp put_token_in_session(conn, token) do
    conn
    |> put_session(:user_token, token)
    |> put_session(:live_socket_id, "users_sessions:#{Base.url_encode64(token)}")
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :user_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn

  defp signed_in_path(_conn), do: ~p"/admin/control-plane"
end
