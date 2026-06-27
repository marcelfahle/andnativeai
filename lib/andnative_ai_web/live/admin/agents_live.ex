defmodule AndnativeAiWeb.Admin.AgentsLive do
  use AndnativeAiWeb, :live_view

  alias AndnativeAi.Memory
  alias AndnativeAi.Runtime.OpenClaw

  @empty_agent %{
    "name" => "",
    "identity" => "Answer from governed memory with concise citations.",
    "model" => "gpt-4.1-mini",
    "status" => "active"
  }

  @impl true
  def mount(_params, _session, socket) do
    tenant = Memory.ensure_demo_tenant!()

    {:ok,
     socket
     |> assign(:page_title, "Agents")
     |> assign(:tenant, tenant)
     |> assign(:editing_agent_id, nil)
     |> assign(:form, to_form(@empty_agent, as: :agent))
     |> reload_agents()}
  end

  @impl true
  def handle_event("validate", %{"agent" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :agent))}
  end

  def handle_event("save", %{"agent" => params}, socket) do
    attrs = Map.merge(params, %{"runtime" => "openclaw"})

    result =
      case socket.assigns.editing_agent_id do
        nil ->
          if length(socket.assigns.agents) >= 2 do
            {:error, :agent_limit}
          else
            Memory.create_agent(socket.assigns.tenant.id, attrs)
          end

        id ->
          socket.assigns.tenant.id
          |> Memory.get_agent!(String.to_integer(id))
          |> Memory.update_agent(attrs)
      end

    socket =
      case result do
        {:ok, _agent} ->
          socket
          |> put_flash(:info, "Agent saved.")
          |> assign(:editing_agent_id, nil)
          |> assign(:form, to_form(@empty_agent, as: :agent))
          |> reload_agents()

        {:error, :agent_limit} ->
          put_flash(socket, :error, "Demo limit is two agents.")

        {:error, changeset} ->
          put_flash(socket, :error, "Agent could not be saved: #{inspect(changeset.errors)}")
      end

    {:noreply, socket}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    agent = Memory.get_agent!(socket.assigns.tenant.id, String.to_integer(id))

    form =
      to_form(
        %{
          "name" => agent.name,
          "identity" => agent.identity,
          "model" => agent.model,
          "status" => agent.status
        },
        as: :agent
      )

    {:noreply, socket |> assign(:editing_agent_id, id) |> assign(:form, form)}
  end

  def handle_event("new", _params, socket) do
    {:noreply,
     socket |> assign(:editing_agent_id, nil) |> assign(:form, to_form(@empty_agent, as: :agent))}
  end

  def handle_event("sync", %{"id" => id}, socket) do
    agent = Memory.get_agent!(socket.assigns.tenant.id, String.to_integer(id))

    socket =
      case OpenClaw.sync_agent(agent) do
        {:ok, _agent} -> put_flash(socket, :info, "Agent synced.")
        {:error, reason} -> put_flash(socket, :error, "Sync failed: #{inspect(reason)}")
      end
      |> reload_agents()

    {:noreply, socket}
  end

  defp reload_agents(socket) do
    assign(socket, :agents, Memory.list_agents(socket.assigns.tenant.id))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-8">
        <section class="flex flex-col gap-2 border-b border-base-300 pb-6 md:flex-row md:items-end md:justify-between">
          <div>
            <p class="text-sm font-medium text-base-content/60">{@tenant.name}</p>
            <h1 class="text-3xl font-semibold tracking-normal">Agents</h1>
          </div>
          <button id="new-agent" class="btn btn-ghost btn-sm" phx-click="new">
            <.icon name="hero-plus" class="size-4" /> New
          </button>
        </section>

        <section class="grid gap-6 lg:grid-cols-[0.9fr_1.1fr]">
          <div class="rounded-lg border border-base-300 bg-base-100 p-5">
            <h2 class="text-base font-semibold">
              {if @editing_agent_id, do: "Edit agent", else: "Create agent"}
            </h2>
            <.form
              for={@form}
              id="agent-form"
              phx-change="validate"
              phx-submit="save"
              class="mt-5 space-y-4"
            >
              <.input field={@form[:name]} label="Name" />
              <.input field={@form[:identity]} type="textarea" label="Identity" />
              <.input field={@form[:model]} label="Model" />
              <.input field={@form[:status]} label="Status" />
              <div class="flex items-center justify-between">
                <span class="badge badge-outline">OpenClaw</span>
                <button id="agent-submit" class="btn btn-primary">
                  <.icon name="hero-check" class="size-4" /> Save
                </button>
              </div>
            </.form>
          </div>

          <div class="rounded-lg border border-base-300 bg-base-100">
            <div class="flex items-center justify-between border-b border-base-300 px-5 py-4">
              <h2 class="text-base font-semibold">Configured agents</h2>
              <span class="badge badge-neutral">{length(@agents)}/2</span>
            </div>
            <div id="agents-list" class="divide-y divide-base-300">
              <div
                :if={@agents == []}
                id="agents-empty"
                class="px-5 py-10 text-sm text-base-content/60"
              >
                No agents.
              </div>
              <div
                :for={agent <- @agents}
                id={"agent-#{agent.id}"}
                class="flex items-center justify-between gap-4 px-5 py-4"
              >
                <div class="min-w-0">
                  <p class="truncate font-medium">{agent.name}</p>
                  <p class="mt-1 truncate text-xs text-base-content/60">
                    {agent.model} · {agent.runtime}
                  </p>
                  <div class="mt-2 flex flex-wrap items-center gap-2 text-xs">
                    <span class="badge badge-outline">{agent.status}</span>
                    <span :if={agent.runtime_ref} class="truncate text-base-content/50">
                      {agent.runtime_ref}
                    </span>
                  </div>
                </div>
                <div class="flex shrink-0 items-center gap-1">
                  <button
                    id={"edit-agent-#{agent.id}"}
                    class="btn btn-ghost btn-sm"
                    phx-click="edit"
                    phx-value-id={agent.id}
                  >
                    <.icon name="hero-pencil-square" class="size-4" />
                  </button>
                  <button
                    id={"sync-agent-#{agent.id}"}
                    class="btn btn-secondary btn-sm"
                    phx-click="sync"
                    phx-value-id={agent.id}
                  >
                    <.icon name="hero-arrow-path" class="size-4" /> Sync
                  </button>
                </div>
              </div>
            </div>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
