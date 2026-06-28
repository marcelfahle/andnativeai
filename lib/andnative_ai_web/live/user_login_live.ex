defmodule AndnativeAiWeb.UserLoginLive do
  use AndnativeAiWeb, :live_view

  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />

    <div class="mx-auto mt-16 w-full max-w-sm space-y-8 px-4">
      <div class="text-center">
        <span class="mx-auto grid size-10 place-items-center rounded bg-base-content text-base-100">
          &amp;
        </span>
        <h1 class="mt-4 text-2xl font-semibold">Sign in</h1>
        <p class="mt-1 text-sm text-base-content/60">&amp;native.ai admin</p>
      </div>

      <.form
        for={@form}
        id="login_form"
        action={~p"/login"}
        phx-update="ignore"
        class="space-y-4"
      >
        <.input
          field={@form[:email]}
          type="email"
          label="Email"
          autocomplete="username"
          required
        />
        <.input
          field={@form[:password]}
          type="password"
          label="Password"
          autocomplete="current-password"
          required
        />
        <.button class="btn btn-primary w-full" variant="primary">
          Sign in
        </.button>
      </.form>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")

    {:ok, assign(socket, form: form, page_title: "Sign in")}
  end
end
