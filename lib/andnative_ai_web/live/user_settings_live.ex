defmodule AndnativeAiWeb.UserSettingsLive do
  use AndnativeAiWeb, :live_view

  alias AndnativeAi.Accounts

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="mx-auto max-w-lg space-y-6">
        <.header>
          Account settings
          <:subtitle>Change your &native.ai admin password.</:subtitle>
        </.header>

        <.form
          for={@password_form}
          id="password_form"
          action={~p"/login?_action=password_updated"}
          method="post"
          phx-change="validate_password"
          phx-submit="update_password"
          phx-trigger-action={@trigger_submit}
          class="space-y-4"
        >
          <input type="hidden" name="user[email]" id="hidden_user_email" value={@current_user.email} />
          <.input
            field={@password_form[:password]}
            type="password"
            label="New password"
            autocomplete="new-password"
            required
          />
          <.input
            field={@password_form[:current_password]}
            name="current_password"
            id="current_password"
            type="password"
            label="Current password"
            value={@current_password}
            autocomplete="current-password"
            required
          />
          <.button variant="primary" phx-disable-with="Saving...">Change password</.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  def mount(_params, _session, socket) do
    password_form =
      socket.assigns.current_user
      |> Accounts.change_user_password()
      |> to_form()

    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign(:current_password, nil)
     |> assign(:trigger_submit, false)
     |> assign(:password_form, password_form)}
  end

  def handle_event("validate_password", params, socket) do
    %{"current_password" => current_password, "user" => user_params} = params

    password_form =
      socket.assigns.current_user
      |> Accounts.change_user_password(user_params)
      |> to_form(action: :validate)

    {:noreply, assign(socket, password_form: password_form, current_password: current_password)}
  end

  def handle_event("update_password", params, socket) do
    %{"current_password" => current_password, "user" => user_params} = params

    case Accounts.update_user_password(socket.assigns.current_user, current_password, user_params) do
      {:ok, user} ->
        password_form =
          user
          |> Accounts.change_user_password(user_params)
          |> to_form()

        {:noreply, assign(socket, trigger_submit: true, password_form: password_form)}

      {:error, changeset} ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end
end
