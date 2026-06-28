defmodule AndnativeAiWeb.Admin.UsersLive do
  use AndnativeAiWeb, :live_view

  alias AndnativeAi.Accounts

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="mx-auto max-w-4xl space-y-6">
        <.header>
          Users
          <:subtitle>Admins with access to the &native.ai control panel.</:subtitle>
          <:actions>
            <.link navigate={~p"/admin/users/invite"} class="btn btn-primary btn-sm">
              <.icon name="hero-user-plus" class="size-4" /> Invite a user
            </.link>
          </:actions>
        </.header>

        <.table id="users" rows={@users}>
          <:col :let={user} label="Email">{user.email}</:col>
          <:col :let={user} label="Status">
            <span :if={user.confirmed_at} class="badge badge-success badge-sm">Active</span>
            <span :if={is_nil(user.confirmed_at)} class="badge badge-warning badge-sm">Invited</span>
          </:col>
          <:col :let={user} label="Joined">
            {Calendar.strftime(user.inserted_at, "%Y-%m-%d")}
          </:col>
          <:action :let={user}>
            <.link
              :if={is_nil(user.confirmed_at)}
              phx-click="resend"
              phx-value-id={user.id}
              data-confirm={"Resend the invitation to #{user.email}?"}
              class="btn btn-ghost btn-xs"
            >
              Resend invite
            </.link>
          </:action>
          <:action :let={user}>
            <.link
              :if={user.id != @current_user.id}
              phx-click="delete"
              phx-value-id={user.id}
              data-confirm={"Delete #{user.email}? This cannot be undone."}
              class="btn btn-ghost btn-xs text-error"
            >
              Delete
            </.link>
          </:action>
        </.table>
      </div>
    </Layouts.app>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, "Users") |> assign_users()}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    if id == to_string(socket.assigns.current_user.id) do
      {:noreply, put_flash(socket, :error, "You can't delete your own account.")}
    else
      socket =
        case Accounts.delete_user(Accounts.get_user!(id)) do
          {:ok, user} ->
            put_flash(socket, :info, "Deleted #{user.email}.")

          {:error, :last_user} ->
            put_flash(socket, :error, "Can't delete the last remaining admin.")
        end

      {:noreply, assign_users(socket)}
    end
  end

  def handle_event("resend", %{"id" => id}, socket) do
    socket =
      case Accounts.resend_user_invitation(
             Accounts.get_user!(id),
             &url(~p"/users/invite/#{&1}")
           ) do
        {:ok, user} ->
          put_flash(socket, :info, "Invitation resent to #{user.email}.")

        {:error, :already_active} ->
          put_flash(socket, :error, "That user has already activated their account.")

        {:error, _reason} ->
          put_flash(
            socket,
            :error,
            "Could not send the invitation email. Check the mailer configuration."
          )
      end

    {:noreply, assign_users(socket)}
  end

  defp assign_users(socket) do
    assign(socket, :users, Accounts.list_users())
  end
end
