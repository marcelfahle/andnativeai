defmodule AndnativeAiWeb.UserForgotPasswordLive do
  use AndnativeAiWeb, :live_view

  alias AndnativeAi.Accounts

  @generic_message "If your email is in our system, you will receive password reset instructions shortly."

  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash}>
      <div class="mt-16 space-y-6">
        <div class="text-center">
          <h1 class="text-2xl font-semibold">Forgot your password?</h1>
          <p class="mt-1 text-sm text-base-content/60">We'll email you a reset link.</p>
        </div>

        <.form for={@form} id="forgot_password_form" phx-submit="send_email" class="space-y-4">
          <.input field={@form[:email]} type="email" label="Email" autocomplete="username" required />
          <.button variant="primary" class="btn btn-primary w-full" phx-disable-with="Sending...">
            Send reset link
          </.button>
        </.form>

        <p class="text-center text-sm">
          <.link navigate={~p"/login"} class="link">Back to sign in</.link>
        </p>
      </div>
    </Layouts.auth>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, assign(socket, form: to_form(%{}, as: "user"), page_title: "Forgot password")}
  end

  def handle_event("send_email", %{"user" => %{"email" => email}}, socket) do
    # Only deliver when the email exists, but always show the same message so we
    # never reveal whether an account exists.
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_reset_password_instructions(
        user,
        &url(~p"/users/reset-password/#{&1}")
      )
    end

    {:noreply,
     socket
     |> put_flash(:info, @generic_message)
     |> redirect(to: ~p"/login")}
  end
end
