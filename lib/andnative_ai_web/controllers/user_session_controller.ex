defmodule AndnativeAiWeb.UserSessionController do
  use AndnativeAiWeb, :controller

  require Logger

  alias AndnativeAi.Accounts
  alias AndnativeAiWeb.UserAuth

  # Re-login after a self-serve password change (phx-trigger-action posts here).
  def create(conn, %{"_action" => "password_updated"} = params) do
    create(conn, params, "Password updated successfully!")
  end

  def create(conn, params) do
    create(conn, params, "Welcome back!")
  end

  defp create(conn, %{"user" => %{"email" => email, "password" => password}}, info)
       when is_binary(email) and is_binary(password) do
    if user = Accounts.get_user_by_email_and_password(email, password) do
      record_platform_access(user)

      conn
      |> put_flash(:info, info)
      |> UserAuth.log_in_user(user)
    else
      # Do not disclose whether the email is registered (no user enumeration).
      conn
      |> put_flash(:error, "Invalid email or password")
      |> put_flash(:email, String.slice(email, 0, 160))
      |> redirect(to: ~p"/login")
    end
  end

  # Malformed or missing credentials (non-browser clients) get the same generic
  # error rather than a 500.
  defp create(conn, _params, _info) do
    conn
    |> put_flash(:error, "Invalid email or password")
    |> redirect(to: ~p"/login")
  end

  # Platform staff are hidden from customer user management (AAI-34), so
  # their access must be visible where it matters: the governance trail.
  # Auditing is best-effort end to end — the tenant lookup is inside the
  # rescue too, so no failure here can ever break a login.
  defp record_platform_access(%{role: "superadmin"} = user) do
    tenant = AndnativeAi.Memory.ensure_demo_tenant!()

    AndnativeAi.Runtime.Audit.record_best_effort(%{
      tenant_id: tenant.id,
      event_kind: "platform_access",
      component: "control_panel",
      actor: user.email,
      status: "signed_in",
      summary: "Platform staff #{user.email} signed in.",
      metadata: %{role: user.role},
      occurred_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  rescue
    error ->
      Logger.warning("Could not record platform access: #{Exception.message(error)}")
      :ok
  end

  defp record_platform_access(_user), do: :ok

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
