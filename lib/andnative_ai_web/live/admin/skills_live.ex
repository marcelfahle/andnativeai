defmodule AndnativeAiWeb.Admin.SkillsLive do
  use AndnativeAiWeb, :live_view

  alias AndnativeAi.Memory
  alias AndnativeAi.Skills

  @impl true
  def mount(_params, _session, socket) do
    tenant = Memory.ensure_demo_tenant!()

    socket =
      socket
      |> assign(:page_title, "Skills")
      |> assign(:tenant, tenant)
      |> assign(:form, to_form(%{}, as: :skill_upload))
      |> reload()
      |> allow_upload(:skill_bundle,
        accept: ~w(.zip .md),
        max_entries: 1,
        max_file_size: 5_000_000,
        auto_upload: false
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("install", _params, socket) do
    actor = actor(socket)

    results =
      consume_uploaded_entries(socket, :skill_bundle, fn %{path: path}, entry ->
        {:ok,
         Skills.install_from_upload(socket.assigns.tenant.id, path, entry.client_name,
           actor: actor
         )}
      end)

    socket =
      case results do
        [{:ok, skill}] ->
          socket
          |> put_flash(:info, "Skill \"#{skill.name}\" v#{skill.version} installed.")
          |> reload()

        [{:error, reason}] ->
          put_flash(socket, :error, "Skill rejected: #{humanize_reason(reason)}")

        [] ->
          put_flash(socket, :error, "Choose a skill bundle (.zip) or SKILL.md first.")
      end

    {:noreply, socket}
  end

  def handle_event("toggle-agent", %{"skill" => skill_id, "agent" => agent_id}, socket) do
    with {skill_id, ""} <- Integer.parse(to_string(skill_id)),
         {agent_id, ""} <- Integer.parse(to_string(agent_id)) do
      tenant_id = socket.assigns.tenant.id
      enabled? = skill_id in Map.get(socket.assigns.enabled_by_agent, agent_id, MapSet.new())

      if enabled? do
        Skills.disable_for_agent(tenant_id, skill_id, agent_id, actor: actor(socket))
      else
        Skills.enable_for_agent(tenant_id, skill_id, agent_id, actor: actor(socket))
      end

      {:noreply, reload(socket)}
    else
      _invalid -> {:noreply, socket}
    end
  end

  def handle_event("remove", %{"id" => id}, socket) do
    case Integer.parse(to_string(id)) do
      {skill_id, ""} ->
        {:ok, skill} =
          Skills.remove_skill(socket.assigns.tenant.id, skill_id, actor: actor(socket))

        {:noreply,
         socket
         |> put_flash(:info, "Skill \"#{skill.name}\" removed.")
         |> reload()}

      _invalid ->
        {:noreply, socket}
    end
  end

  defp reload(socket) do
    tenant_id = socket.assigns.tenant.id
    agents = Memory.list_agents(tenant_id)

    enabled_by_agent =
      Map.new(agents, fn agent ->
        {agent.id, MapSet.new(Skills.enabled_skill_ids(agent.id))}
      end)

    socket
    |> assign(:skills, Skills.list_skills(tenant_id))
    |> assign(:agents, agents)
    |> assign(:enabled_by_agent, enabled_by_agent)
  end

  defp actor(socket) do
    (socket.assigns.current_user && socket.assigns.current_user.email) || "Admin"
  end

  defp humanize_reason(:contains_scripts),
    do: "prompt-pack skills only — this bundle contains executable scripts."

  defp humanize_reason(:contains_tool_grants),
    do: "prompt-pack skills only — this bundle requests tool grants."

  defp humanize_reason(:contains_dynamic_injection),
    do: "this bundle contains dynamic shell-injection syntax."

  defp humanize_reason(:missing_skill_md), do: "no SKILL.md found in the bundle."
  defp humanize_reason(:missing_frontmatter), do: "SKILL.md has no frontmatter."
  defp humanize_reason({:missing_field, field}), do: "frontmatter is missing \"#{field}\"."
  defp humanize_reason(other), do: inspect(other)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div id="skills-library" class="mx-auto max-w-5xl space-y-8">
        <section class="flex flex-col gap-2 border-b border-base-300 pb-6">
          <p class="text-sm font-medium text-base-content/60">{@tenant.name}</p>
          <h1 class="text-3xl font-semibold tracking-normal">Skills</h1>
          <p class="max-w-2xl text-sm leading-6 text-base-content/60">
            Prompt-pack skills (Agent Skills standard) teach agents <span class="italic">how</span>
            to do specific tasks. Installs are version-pinned, per-agent, and every
            decision lands on the audit timeline. Bundles with executable scripts are
            rejected.
          </p>
        </section>

        <section class="rounded-lg border border-base-300 bg-base-100 p-5">
          <h2 class="text-base font-semibold">Install a skill</h2>
          <p class="mt-1 text-sm text-base-content/60">
            Upload a SKILL.md or a bundle .zip (SKILL.md + references/). Works with any
            skill from the open ecosystem that ships without scripts.
          </p>

          <.form
            for={@form}
            id="skill-install-form"
            phx-change="validate"
            phx-submit="install"
            class="mt-4 space-y-4"
          >
            <.live_file_input
              upload={@uploads.skill_bundle}
              class="file-input file-input-bordered w-full"
            />
            <div
              :for={entry <- @uploads.skill_bundle.entries}
              class="flex items-center justify-between text-sm"
            >
              <span class="truncate">{entry.client_name}</span>
              <span class="tabular-nums text-base-content/50">{entry.progress}%</span>
            </div>
            <div class="flex justify-end">
              <button id="skill-install-submit" class="btn btn-primary">
                <.icon name="hero-puzzle-piece" class="size-4" /> Install
              </button>
            </div>
          </.form>
        </section>

        <section class="rounded-lg border border-base-300 bg-base-100">
          <div class="flex items-center justify-between border-b border-base-300 px-5 py-4">
            <h2 class="text-base font-semibold">Installed skills</h2>
            <span class="text-xs tabular-nums text-base-content/50">{length(@skills)}</span>
          </div>

          <div
            :if={@skills == []}
            id="skills-empty"
            class="px-5 py-10 text-sm text-base-content/60"
          >
            No skills installed yet. Try a prompt-only skill from the open ecosystem —
            the marketing pack is MIT-licensed.
          </div>

          <div :if={@skills != []} class="divide-y divide-base-300/70">
            <div :for={skill <- @skills} id={"skill-#{skill.id}"} class="px-5 py-4">
              <div class="flex flex-wrap items-start justify-between gap-3">
                <div class="min-w-0">
                  <div class="flex flex-wrap items-baseline gap-2">
                    <p class="font-mono text-sm font-semibold">{skill.name}</p>
                    <span class="font-mono text-[11px] text-base-content/45">
                      v{skill.version}
                    </span>
                    <span
                      :if={skill.license}
                      class="rounded border border-base-300 px-1.5 py-0.5 text-[10px] font-medium uppercase tracking-wide text-base-content/50"
                    >
                      {skill.license}
                    </span>
                  </div>
                  <p class="mt-1 max-w-2xl text-sm leading-6 text-base-content/60">
                    {skill.description}
                  </p>
                </div>

                <button
                  id={"remove-skill-#{skill.id}"}
                  class="btn btn-ghost btn-sm text-error"
                  phx-click="remove"
                  phx-value-id={skill.id}
                  data-confirm="Remove this skill from the library?"
                >
                  <.icon name="hero-trash" class="size-4" />
                </button>
              </div>

              <div :if={@agents != []} class="mt-3 flex flex-wrap items-center gap-4">
                <label
                  :for={agent <- @agents}
                  class="flex cursor-pointer items-center gap-2 text-xs text-base-content/70"
                >
                  <input
                    type="checkbox"
                    id={"skill-#{skill.id}-agent-#{agent.id}"}
                    class="toggle toggle-sm"
                    checked={
                      MapSet.member?(Map.get(@enabled_by_agent, agent.id, MapSet.new()), skill.id)
                    }
                    phx-click="toggle-agent"
                    phx-value-skill={skill.id}
                    phx-value-agent={agent.id}
                  /> enabled for {agent.name}
                </label>
              </div>
            </div>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
