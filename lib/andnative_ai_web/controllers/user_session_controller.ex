defmodule AndnativeAiWeb.UserSessionController do
  use AndnativeAiWeb, :controller

  alias AndnativeAi.Accounts
  alias AndnativeAiWeb.UserAuth

  def create(conn, %{"user" => %{"email" => email, "password" => password}})
      when is_binary(email) and is_binary(password) do
    if user = Accounts.get_user_by_email_and_password(email, password) do
      conn
      |> put_flash(:info, "Welcome back!")
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
  def create(conn, _params) do
    conn
    |> put_flash(:error, "Invalid email or password")
    |> redirect(to: ~p"/login")
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
