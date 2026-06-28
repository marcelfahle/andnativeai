defmodule AndnativeAiWeb.UserSessionController do
  use AndnativeAiWeb, :controller

  alias AndnativeAi.Accounts
  alias AndnativeAiWeb.UserAuth

  def create(conn, %{"user" => user_params}) do
    %{"email" => email, "password" => password} = user_params

    if user = Accounts.get_user_by_email_and_password(email, password) do
      conn
      |> put_flash(:info, "Welcome back!")
      |> UserAuth.log_in_user(user, user_params)
    else
      # Do not disclose whether the email is registered (no user enumeration).
      conn
      |> put_flash(:error, "Invalid email or password")
      |> put_flash(:email, String.slice(email || "", 0, 160))
      |> redirect(to: ~p"/login")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
