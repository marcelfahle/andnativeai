defmodule AndnativeAiWeb.Admin.UsersLive do
  use AndnativeAiWeb, :live_view

  alias AndnativeAi.Accounts
  alias AndnativeAi.Accounts.User

  # Platform accounts are hidden from CUSTOMER admins — not from each
  # other. Staff hiding themselves from staff serves no one, and on our
  # own appliance it makes the page look empty.
  # An unknown id is always "hidden" — no viewer makes a missing row real.
  defp hidden?(nil, _viewer), do: true
  defp hidden?(_user, %{role: "superadmin"}), do: false
  defp hidden?(user, _viewer), do: User.superadmin?(user)

  defp visible_users(%{role: "superadmin"}), do: Accounts.list_users()
  defp visible_users(_viewer), do: Accounts.list_customer_users()

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="mx-auto max-w-4xl space-y-6">
        <.header>
          Users
          <:subtitle>Admins with access to the &amp;native.ai control panel.</:subtitle>
          <:actions>
            <.link navigate={~p"/admin/users/invite"} class="btn btn-primary btn-sm">
              <.icon name="hero-user-plus" class="size-4" /> Invite a user
            </.link>
          </:actions>
        </.header>

        <.table id="users" rows={@streams.users} row_item={fn {_id, user} -> user end}>
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
    {:ok,
     socket
     |> assign(:page_title, "Users")
     |> stream(:users, visible_users(socket.assigns.current_user))}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    # Look the user up first (no raise on a stale/crafted id) and compare ids as
    # integers, so a crafted event can't bypass the self-delete guard. The last
    # active admin is refused at the context layer.
    user = Accounts.get_user(id)

    socket =
      cond do
        hidden?(user, socket.assigns.current_user) ->
          put_flash(socket, :error, "That user no longer exists.")

        user.id == socket.assigns.current_user.id ->
          put_flash(socket, :error, "You can't delete your own account.")

        true ->
          case Accounts.delete_user(user) do
            {:ok, deleted} ->
              socket
              |> put_flash(:info, "Deleted #{deleted.email}.")
              |> stream_delete(:users, deleted)

            {:error, :last_user} ->
              put_flash(socket, :error, "Can't delete the last remaining admin.")

            {:error, _changeset} ->
              put_flash(socket, :error, "Could not delete that user.")
          end
      end

    {:noreply, socket}
  end

  def handle_event("resend", %{"id" => id}, socket) do
    user = Accounts.get_user(id)

    socket =
      cond do
        hidden?(user, socket.assigns.current_user) ->
          put_flash(socket, :error, "That user no longer exists.")

        true ->
          case Accounts.resend_user_invitation(user, &url(~p"/users/invite/#{&1}")) do
            {:ok, invited} ->
              put_flash(socket, :info, "Invitation resent to #{invited.email}.")

            {:error, :already_active} ->
              put_flash(socket, :error, "That user has already activated their account.")

            {:error, _reason} ->
              put_flash(
                socket,
                :error,
                "Could not send the invitation email. Check the mailer configuration."
              )
          end
      end

    {:noreply, socket}
  end
end
