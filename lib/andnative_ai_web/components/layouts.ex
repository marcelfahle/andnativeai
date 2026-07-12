defmodule AndnativeAiWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use AndnativeAiWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_user, :map,
    default: nil,
    doc: "the currently authenticated user, when present"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="border-b border-base-300 bg-base-100 px-4 sm:px-6 lg:px-8">
      <div class="mx-auto flex max-w-6xl flex-col gap-3 py-4 md:flex-row md:items-center md:justify-between">
        <.link navigate={~p"/admin/agents"} class="flex w-fit items-center gap-3">
          <span class="grid size-9 place-items-center rounded bg-base-content text-sm font-semibold text-base-100">
            &amp;
          </span>
          <span class="font-semibold tracking-normal">&amp;native.ai</span>
        </.link>

        <nav class="flex flex-wrap items-center gap-1">
          <.link navigate={~p"/admin/control-plane"} class="btn btn-ghost btn-sm">
            <.icon name="hero-shield-check" class="size-4" /> Control
          </.link>
          <.link navigate={~p"/admin/memory"} class="btn btn-ghost btn-sm">
            <.icon name="hero-circle-stack" class="size-4" /> Memory
          </.link>
          <.link navigate={~p"/admin/agents"} class="btn btn-ghost btn-sm">
            <.icon name="hero-cpu-chip" class="size-4" /> Agents
          </.link>
          <.link navigate={~p"/admin/sources"} class="btn btn-ghost btn-sm">
            <.icon name="hero-folder" class="size-4" /> Sources
          </.link>
          <.link navigate={~p"/admin/slack"} class="btn btn-ghost btn-sm">
            <.icon name="hero-chat-bubble-left-right" class="size-4" /> Slack
          </.link>
          <.link navigate={~p"/admin/runtime"} class="btn btn-ghost btn-sm">
            <.icon name="hero-command-line" class="size-4" /> Runtime
          </.link>
          <.theme_toggle />
          <div :if={@current_user} class="flex items-center gap-2 pl-2">
            <span class="hidden text-xs text-base-content/60 sm:inline">{@current_user.email}</span>
            <.link navigate={~p"/admin/users"} class="btn btn-ghost btn-sm">
              <.icon name="hero-users" class="size-4" /> Users
            </.link>
            <.link navigate={~p"/users/settings"} class="btn btn-ghost btn-sm">
              <.icon name="hero-cog-6-tooth" class="size-4" /> Settings
            </.link>
            <.link href={~p"/logout"} method="delete" class="btn btn-ghost btn-sm">
              <.icon name="hero-arrow-right-on-rectangle" class="size-4" /> Log out
            </.link>
          </div>
        </nav>
      </div>
    </header>

    <main class="px-4 py-8 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-6xl">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Renders a minimal, centered layout for unauthenticated pages such as login.

  Includes the flash group but omits the admin navigation.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  slot :inner_block, required: true

  def auth(assigns) do
    ~H"""
    <main class="px-4 py-8 sm:px-6 lg:px-8">
      <div class="mx-auto w-full max-w-sm">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
