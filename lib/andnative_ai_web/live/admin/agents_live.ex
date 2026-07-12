defmodule AndnativeAiWeb.Admin.AgentsLive do
  use AndnativeAiWeb, :live_view

  alias AndnativeAi.Accounts.User
  alias AndnativeAi.Memory
  alias AndnativeAi.Memory.Agent
  alias AndnativeAi.Runtime.{ModelPolicy, OpenClaw}
  alias AndnativeAi.Skills

  @empty_agent %{
    "name" => "",
    "identity" => "Answer from governed memory with concise citations.",
    "role" => "general",
    "status" => "active"
  }

  @role_labels %{
    "general" => "General",
    "marketing" => "Marketing",
    "ops" => "Ops",
    "research" => "Research"
  }

  @impl true
  def mount(_params, _session, socket) do
    tenant = Memory.ensure_demo_tenant!()

    {:ok,
     socket
     |> assign(:page_title, "Agents")
     |> assign(:tenant, tenant)
     |> assign(:superadmin?, User.superadmin?(socket.assigns.current_user))
     |> assign(:editing_agent_id, nil)
     |> assign(:policy_agent, nil)
     |> assign(:form, to_form(@empty_agent, as: :agent))
     |> assign(:policy_form, nil)
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
          "role" => agent.role,
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

  # Model policy is platform-staff territory: every handler below re-checks
  # the role server-side; the UI merely hides the affordances.
  def handle_event("edit-policy", %{"id" => id}, socket) do
    if socket.assigns.superadmin? do
      agent = Memory.get_agent!(socket.assigns.tenant.id, String.to_integer(id))

      params =
        %{"model" => agent.model || ""}
        |> Map.merge(
          Map.new(ModelPolicy.capabilities(), fn capability ->
            {capability, agent.model_policy[capability] || ""}
          end)
        )

      {:noreply,
       socket
       |> assign(:policy_agent, agent)
       |> assign(:policy_form, to_form(params, as: :policy))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("close-policy", _params, socket) do
    {:noreply, socket |> assign(:policy_agent, nil) |> assign(:policy_form, nil)}
  end

  def handle_event("save-policy", %{"policy" => params}, socket) do
    with true <- socket.assigns.superadmin?,
         %Agent{} = agent <- socket.assigns.policy_agent do
      attrs = %{
        "model" => params["model"],
        "model_policy" => Map.take(params, ModelPolicy.capabilities())
      }

      actor = (socket.assigns.current_user && socket.assigns.current_user.email) || "Superadmin"

      socket =
        case Memory.update_agent_model_policy(agent, attrs, actor: actor) do
          {:ok, _agent} ->
            socket
            |> put_flash(:info, "Model policy updated for #{agent.name}.")
            |> assign(:policy_agent, nil)
            |> assign(:policy_form, nil)
            |> reload_agents()

          {:error, changeset} ->
            put_flash(socket, :error, "Policy not saved: #{inspect(changeset.errors)}")
        end

      {:noreply, socket}
    else
      _not_allowed -> {:noreply, socket}
    end
  end

  defp reload_agents(socket) do
    agents = Memory.list_agents(socket.assigns.tenant.id)

    skills_by_agent =
      Map.new(agents, fn agent ->
        {agent.id, Skills.enabled_skills(agent.id)}
      end)

    socket
    |> assign(:agents, agents)
    |> assign(:skills_by_agent, skills_by_agent)
  end

  defp role_label(role), do: Map.get(@role_labels, role, role)

  defp role_options, do: Enum.map(Agent.roles(), &{Map.get(@role_labels, &1, &1), &1})

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
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
          <div class="space-y-6">
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
                <.input field={@form[:role]} type="select" label="Role" options={role_options()} />
                <.input field={@form[:status]} label="Status" />
                <div class="flex items-center justify-between">
                  <span class="badge badge-outline">OpenClaw</span>
                  <button id="agent-submit" class="btn btn-primary">
                    <.icon name="hero-check" class="size-4" /> Save
                  </button>
                </div>
              </.form>
            </div>

            <div
              :if={@superadmin? && @policy_agent}
              id="model-policy-panel"
              class="rounded-lg border border-warning/40 bg-base-100 p-5"
            >
              <div class="flex items-center justify-between">
                <div>
                  <h2 class="text-base font-semibold">Model policy — {@policy_agent.name}</h2>
                  <p class="mt-1 text-xs text-base-content/60">
                    Platform staff only. Changes are recorded on the governance trail.
                  </p>
                </div>
                <button id="close-policy" class="btn btn-ghost btn-xs" phx-click="close-policy">
                  <.icon name="hero-x-mark" class="size-4" />
                </button>
              </div>
              <.form
                for={@policy_form}
                id="model-policy-form"
                phx-submit="save-policy"
                class="mt-4 space-y-3"
              >
                <.input
                  field={@policy_form[:model]}
                  label="Base model"
                  placeholder={ModelPolicy.default_model()}
                />
                <div class="grid grid-cols-2 gap-3">
                  <.input
                    :for={capability <- ModelPolicy.capabilities()}
                    field={@policy_form[capability]}
                    label={"#{String.capitalize(capability)} override"}
                    placeholder="inherit"
                  />
                </div>
                <div class="flex justify-end">
                  <button id="policy-submit" class="btn btn-warning btn-sm">
                    <.icon name="hero-shield-check" class="size-4" /> Apply policy
                  </button>
                </div>
              </.form>
            </div>
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
                  <div class="mt-1 flex flex-wrap items-center gap-2 text-xs">
                    <span class="badge badge-primary badge-outline">{role_label(agent.role)}</span>
                    <span class="badge badge-outline">{agent.status}</span>
                    <span
                      :if={@superadmin?}
                      id={"agent-model-#{agent.id}"}
                      class="text-base-content/60"
                    >
                      {ModelPolicy.resolve(agent, :chat)}
                    </span>
                  </div>
                  <div
                    :if={@skills_by_agent[agent.id] != []}
                    class="mt-2 flex flex-wrap items-center gap-1.5 text-xs"
                  >
                    <span
                      :for={skill <- @skills_by_agent[agent.id]}
                      class="badge badge-ghost badge-sm"
                    >
                      {skill.name} v{skill.version}
                    </span>
                  </div>
                </div>
                <div class="flex shrink-0 items-center gap-1">
                  <button
                    :if={@superadmin?}
                    id={"policy-agent-#{agent.id}"}
                    class="btn btn-ghost btn-sm"
                    phx-click="edit-policy"
                    phx-value-id={agent.id}
                    title="Model policy"
                  >
                    <.icon name="hero-cpu-chip" class="size-4" />
                  </button>
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
