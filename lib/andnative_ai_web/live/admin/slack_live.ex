defmodule AndnativeAiWeb.Admin.SlackLive do
  use AndnativeAiWeb, :live_view

  alias AndnativeAi.Memory
  alias AndnativeAi.Slack.Installations

  @impl true
  def mount(_params, _session, socket) do
    tenant = Memory.ensure_demo_tenant!()

    slack_sources =
      tenant.id
      |> Memory.list_sources()
      |> Enum.filter(&(&1.source_type == "slack_channel"))

    installations = Installations.list_installations(tenant.id)
    oauth_config = oauth_config(tenant.id)

    {:ok,
     socket
     |> assign(:page_title, "Slack")
     |> assign(:tenant, tenant)
     |> assign(:slack_sources, slack_sources)
     |> assign(:installations, installations)
     |> assign(:connection_status, connection_status(installations))
     |> assign(:oauth_config, oauth_config)
     |> assign(:oauth_configured?, Installations.oauth_configured?(tenant.id))}
  end

  @impl true
  def handle_event("save_oauth_config", %{"oauth_config" => params}, socket) do
    case Installations.upsert_oauth_config(socket.assigns.tenant.id, params) do
      {:ok, _config} ->
        {:noreply,
         socket
         |> put_flash(:info, "Slack OAuth app settings saved.")
         |> refresh()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Slack OAuth app settings could not be saved.")}
    end
  end

  defp connection_status(installations) do
    cond do
      installations != [] ->
        "oauth installed"

      Installations.configured_app_token?() and Installations.env_fallback_configured?() ->
        "env configured"

      Installations.configured_app_token?() ->
        "socket only"

      true ->
        "disabled"
    end
  end

  defp refresh(socket) do
    tenant = socket.assigns.tenant
    installations = Installations.list_installations(tenant.id)

    socket
    |> assign(:installations, installations)
    |> assign(:connection_status, connection_status(installations))
    |> assign(:oauth_config, oauth_config(tenant.id))
    |> assign(:oauth_configured?, Installations.oauth_configured?(tenant.id))
  end

  defp oauth_config(tenant_id) do
    settings = Installations.oauth_settings(tenant_id)

    redirect_uri =
      if settings.redirect_uri == "",
        do: url(~p"/slack/oauth/callback"),
        else: settings.redirect_uri

    %{settings | redirect_uri: redirect_uri}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-8">
        <section class="border-b border-base-300 pb-6">
          <p class="text-sm font-medium text-base-content/60">{@tenant.name}</p>
          <h1 class="text-3xl font-semibold tracking-normal">Slack</h1>
        </section>

        <section class="grid gap-6 md:grid-cols-3">
          <div class="rounded-lg border border-base-300 bg-base-100 p-5">
            <p class="text-sm text-base-content/60">Socket Mode</p>
            <p id="slack-connection-status" class="mt-2 text-xl font-semibold">
              {@connection_status}
            </p>
          </div>
          <div class="rounded-lg border border-base-300 bg-base-100 p-5">
            <p class="text-sm text-base-content/60">Channels</p>
            <p class="mt-2 text-xl font-semibold">{length(@slack_sources)}</p>
          </div>
          <div class="rounded-lg border border-base-300 bg-base-100 p-5">
            <p class="text-sm text-base-content/60">Workspaces</p>
            <p class="mt-2 text-xl font-semibold">{length(@installations)}</p>
          </div>
        </section>

        <section class="rounded-lg border border-base-300 bg-base-100 p-5">
          <div class="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
            <div>
              <h2 class="text-base font-semibold">Workspace connection</h2>
              <p class="mt-1 text-sm text-base-content/60">
                OAuth installs store the workspace bot token for Socket Mode event routing.
              </p>
            </div>
            <.link
              href={~p"/slack/install"}
              class={[
                "btn btn-primary",
                !@oauth_configured? && "btn-disabled"
              ]}
            >
              <.icon name="hero-arrow-top-right-on-square" class="size-4" /> Connect Slack
            </.link>
          </div>
          <p :if={!@oauth_configured?} class="mt-3 text-sm text-error">
            Save Slack Client ID and Client Secret to enable OAuth installs.
          </p>
        </section>

        <section class="rounded-lg border border-base-300 bg-base-100">
          <div class="border-b border-base-300 px-5 py-4">
            <h2 class="text-base font-semibold">OAuth app settings</h2>
          </div>
          <form id="slack-oauth-config-form" phx-submit="save_oauth_config" class="p-5">
            <div class="grid gap-4 md:grid-cols-2">
              <label class="form-control">
                <span class="label">
                  <span class="label-text">Client ID</span>
                </span>
                <input
                  name="oauth_config[client_id]"
                  value={@oauth_config.client_id}
                  class="input input-bordered"
                  autocomplete="off"
                />
              </label>
              <label class="form-control">
                <span class="label">
                  <span class="label-text">Client Secret</span>
                </span>
                <input
                  type="password"
                  name="oauth_config[client_secret]"
                  value=""
                  placeholder={
                    if @oauth_config.client_secret_set?,
                      do: "Saved; leave blank to keep",
                      else: "Client secret"
                  }
                  class="input input-bordered"
                  autocomplete="new-password"
                />
              </label>
              <label class="form-control md:col-span-2">
                <span class="label">
                  <span class="label-text">Redirect URI</span>
                </span>
                <input
                  name="oauth_config[redirect_uri]"
                  value={@oauth_config.redirect_uri}
                  class="input input-bordered"
                  autocomplete="off"
                />
              </label>
              <label class="form-control md:col-span-2">
                <span class="label">
                  <span class="label-text">Bot scopes</span>
                </span>
                <input
                  name="oauth_config[bot_scopes]"
                  value={@oauth_config.bot_scopes}
                  class="input input-bordered"
                  autocomplete="off"
                />
              </label>
            </div>
            <div class="mt-5 flex justify-end">
              <button type="submit" class="btn btn-secondary">
                <.icon name="hero-check" class="size-4" /> Save settings
              </button>
            </div>
          </form>
        </section>

        <section class="rounded-lg border border-base-300 bg-base-100">
          <div class="border-b border-base-300 px-5 py-4">
            <h2 class="text-base font-semibold">Installed workspaces</h2>
          </div>
          <div id="slack-installations" class="divide-y divide-base-300">
            <div
              :if={@installations == []}
              id="slack-installations-empty"
              class="px-5 py-10 text-sm text-base-content/60"
            >
              No OAuth workspace installs.
            </div>
            <div
              :for={installation <- @installations}
              id={"slack-installation-#{installation.id}"}
              class="px-5 py-4"
            >
              <div class="flex flex-col gap-2 md:flex-row md:items-center md:justify-between">
                <div>
                  <p class="font-medium">{installation.team_name}</p>
                  <p class="mt-1 text-xs text-base-content/60">{installation.team_id}</p>
                </div>
                <span class="badge badge-outline">{installation.status}</span>
              </div>
            </div>
          </div>
        </section>

        <section class="rounded-lg border border-base-300 bg-base-100">
          <div class="border-b border-base-300 px-5 py-4">
            <h2 class="text-base font-semibold">Invited channels</h2>
          </div>
          <div id="slack-channels" class="divide-y divide-base-300">
            <div
              :if={@slack_sources == []}
              id="slack-channels-empty"
              class="px-5 py-10 text-sm text-base-content/60"
            >
              No channels.
            </div>
            <div :for={source <- @slack_sources} id={"slack-source-#{source.id}"} class="px-5 py-4">
              <p class="font-medium">{source.name}</p>
              <p class="mt-1 text-xs text-base-content/60">{source.source_id}</p>
              <span class="mt-2 badge badge-outline">{source.status}</span>
            </div>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
