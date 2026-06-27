defmodule AndnativeAiWeb.Admin.RuntimeLive do
  use AndnativeAiWeb, :live_view

  alias AndnativeAi.Memory
  alias AndnativeAi.Runtime.OpenClaw

  @impl true
  def mount(_params, _session, socket) do
    tenant = Memory.ensure_demo_tenant!()

    {:ok,
     socket
     |> assign(:page_title, "Runtime")
     |> assign(:tenant, tenant)
     |> reload_runtime()}
  end

  @impl true
  def handle_event("sync", %{"id" => id}, socket) do
    agent = Memory.get_agent!(socket.assigns.tenant.id, String.to_integer(id))

    socket =
      case OpenClaw.sync_agent(agent) do
        {:ok, _agent} -> put_flash(socket, :info, "Runtime synced.")
        {:error, reason} -> put_flash(socket, :error, "Runtime sync failed: #{inspect(reason)}")
      end
      |> reload_runtime()

    {:noreply, socket}
  end

  defp reload_runtime(socket) do
    agents = Memory.list_agents(socket.assigns.tenant.id)
    health = Enum.map(agents, &{&1, OpenClaw.health(&1)})
    socket |> assign(:agents, agents) |> assign(:health, health)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-8">
        <section class="border-b border-base-300 pb-6">
          <p class="text-sm font-medium text-base-content/60">{@tenant.name}</p>
          <h1 class="text-3xl font-semibold tracking-normal">Runtime</h1>
        </section>

        <section class="rounded-lg border border-base-300 bg-base-100">
          <div class="flex items-center justify-between border-b border-base-300 px-5 py-4">
            <h2 class="text-base font-semibold">OpenClaw</h2>
            <span class="badge badge-neutral">{length(@agents)}</span>
          </div>
          <div id="runtime-agents" class="divide-y divide-base-300">
            <div
              :if={@health == []}
              id="runtime-empty"
              class="px-5 py-10 text-sm text-base-content/60"
            >
              No synced agents.
            </div>
            <div
              :for={{agent, health} <- @health}
              id={"runtime-agent-#{agent.id}"}
              class="flex items-center justify-between gap-4 px-5 py-4"
            >
              <div class="min-w-0">
                <p class="font-medium">{agent.name}</p>
                <p class="mt-1 truncate text-xs text-base-content/60">{health.config_path}</p>
                <div class="mt-2 flex flex-wrap gap-2">
                  <span class="badge badge-outline">{agent.status}</span>
                  <span class={[
                    "badge",
                    health.config_exists? && "badge-success",
                    !health.config_exists? && "badge-warning"
                  ]}>
                    {if health.config_exists?, do: "config ready", else: "not synced"}
                  </span>
                </div>
              </div>
              <button
                id={"runtime-sync-#{agent.id}"}
                class="btn btn-secondary btn-sm"
                phx-click="sync"
                phx-value-id={agent.id}
              >
                <.icon name="hero-arrow-path" class="size-4" /> Sync
              </button>
            </div>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
