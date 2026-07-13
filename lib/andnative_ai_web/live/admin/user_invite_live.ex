defmodule AndnativeAiWeb.Admin.UserInviteLive do
  use AndnativeAiWeb, :live_view

  alias AndnativeAi.Accounts

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="mx-auto max-w-lg space-y-6">
        <.header>
          Invite a user
          <:subtitle>They'll get an email to set a password and activate their account.</:subtitle>
        </.header>

        <.form
          for={@form}
          id="invite_form"
          phx-change="validate"
          phx-submit="invite"
          class="space-y-4"
        >
          <.input field={@form[:email]} type="email" label="Email" autocomplete="off" required />
          <.button variant="primary" phx-disable-with="Sending...">Send invitation</.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, assign(socket, form: to_form(%{}, as: "user"), page_title: "Invite user")}
  end

  def handle_event("validate", %{"user" => _user_params}, socket) do
    {:noreply, socket}
  end

  def handle_event("invite", %{"user" => %{"email" => email}}, socket) do
    case Accounts.invite_user(email, &url(~p"/users/invite/#{&1}"),
           actor: socket.assigns.current_user
         ) do
      {:ok, user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Invitation sent to #{user.email}.")
         |> assign(form: to_form(%{}, as: "user"))}

      {:error, :already_active_superadmin} ->
        {:noreply, put_flash(socket, :error, "That address is already a platform account.")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "user", action: :insert))}
    end
  end
end
