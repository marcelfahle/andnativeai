defmodule AndnativeAiWeb.UserAcceptInvitationLive do
  use AndnativeAiWeb, :live_view

  alias AndnativeAi.Accounts

  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash}>
      <div class="mt-16 space-y-6">
        <div class="text-center">
          <h1 class="text-2xl font-semibold">Activate your account</h1>
          <p class="mt-1 text-sm text-base-content/60">Set a password to finish signing up.</p>
        </div>

        <.form
          for={@form}
          id="accept_invitation_form"
          phx-change="validate"
          phx-submit="accept"
          class="space-y-4"
        >
          <.input
            field={@form[:password]}
            type="password"
            label="Password"
            autocomplete="new-password"
            required
          />
          <.button variant="primary" class="btn btn-primary w-full" phx-disable-with="Activating...">
            Set password
          </.button>
        </.form>
      </div>
    </Layouts.auth>
    """
  end

  def mount(%{"token" => token}, _session, socket) do
    case Accounts.get_user_by_invite_token(token) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Invitation link is invalid or it has expired.")
         |> redirect(to: ~p"/login")}

      user ->
        form = to_form(Accounts.change_user_password(user), as: "user")
        {:ok, assign(socket, user: user, form: form, page_title: "Activate account")}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    form =
      socket.assigns.user
      |> Accounts.change_user_password(user_params)
      |> to_form(as: "user", action: :validate)

    {:noreply, assign(socket, form: form)}
  end

  def handle_event("accept", %{"user" => user_params}, socket) do
    case Accounts.accept_invitation(socket.assigns.user, user_params) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Account activated. Please log in.")
         |> redirect(to: ~p"/login")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "user", action: :insert))}
    end
  end
end
