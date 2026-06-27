defmodule AndnativeAiWeb.Admin.SlackLive do
  use AndnativeAiWeb, :live_view

  alias AndnativeAi.Memory

  @impl true
  def mount(_params, _session, socket) do
    tenant = Memory.ensure_demo_tenant!()

    slack_sources =
      tenant.id
      |> Memory.list_sources()
      |> Enum.filter(&(&1.source_type == "slack_channel"))

    {:ok,
     socket
     |> assign(:page_title, "Slack")
     |> assign(:tenant, tenant)
     |> assign(:slack_sources, slack_sources)
     |> assign(:connection_status, connection_status())}
  end

  defp connection_status do
    app = System.get_env("SLACK_APP_TOKEN", "")
    bot = System.get_env("SLACK_BOT_TOKEN", "")
    user = System.get_env("SLACK_BOT_USER_ID", "")

    if configured?(app) and configured?(bot) and user != "", do: "configured", else: "disabled"
  end

  defp configured?(value), do: value != "" and not String.contains?(value, "replace-me")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
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
            <p class="text-sm text-base-content/60">Scope</p>
            <p class="mt-2 text-xl font-semibold">Public</p>
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
