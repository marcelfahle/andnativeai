defmodule AndnativeAiWeb.UserResetPasswordLive do
  use AndnativeAiWeb, :live_view

  alias AndnativeAi.Accounts

  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash}>
      <div class="mt-16 space-y-6">
        <div class="text-center">
          <h1 class="text-2xl font-semibold">Reset password</h1>
          <p class="mt-1 text-sm text-base-content/60">Choose a new password.</p>
        </div>

        <.form
          for={@form}
          id="reset_password_form"
          phx-change="validate"
          phx-submit="reset_password"
          class="space-y-4"
        >
          <.input
            field={@form[:password]}
            type="password"
            label="New password"
            autocomplete="new-password"
            required
          />
          <.button variant="primary" class="btn btn-primary w-full" phx-disable-with="Resetting...">
            Reset password
          </.button>
        </.form>

        <p class="text-center text-sm">
          <.link navigate={~p"/login"} class="link">Back to sign in</.link>
        </p>
      </div>
    </Layouts.auth>
    """
  end

  def mount(%{"token" => token}, _session, socket) do
    case Accounts.get_user_by_reset_password_token(token) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Reset link is invalid or it has expired.")
         |> redirect(to: ~p"/login")}

      user ->
        form = to_form(Accounts.change_user_password(user), as: "user")
        {:ok, assign(socket, user: user, form: form, page_title: "Reset password")}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    form =
      socket.assigns.user
      |> Accounts.change_user_password(user_params)
      |> to_form(as: "user", action: :validate)

    {:noreply, assign(socket, form: form)}
  end

  def handle_event("reset_password", %{"user" => user_params}, socket) do
    case Accounts.reset_user_password(socket.assigns.user, user_params) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Password reset successfully. Please log in.")
         |> redirect(to: ~p"/login")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "user", action: :insert))}
    end
  end
end
