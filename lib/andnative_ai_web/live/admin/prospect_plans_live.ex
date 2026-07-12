defmodule AndnativeAiWeb.Admin.ProspectPlansLive do
  use AndnativeAiWeb, :live_view

  alias AndnativeAi.Memory
  alias AndnativeAi.Prospects
  alias AndnativeAi.Prospects.ProspectPlan

  @impl true
  def mount(_params, _session, socket) do
    tenant = Memory.ensure_demo_tenant!()

    {:ok,
     socket
     |> assign(:page_title, "Discover")
     |> assign(:tenant, tenant)
     |> assign(:form, new_form(tenant))
     |> assign(:plans, Prospects.list_plans(tenant.id))}
  end

  @impl true
  def handle_event("validate", %{"prospect_plan" => params}, socket) do
    changeset =
      %ProspectPlan{tenant_id: socket.assigns.tenant.id}
      |> Prospects.change_plan(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"prospect_plan" => params}, socket) do
    case Prospects.create_plan(socket.assigns.tenant.id, params) do
      {:ok, plan} ->
        {:noreply,
         socket
         |> put_flash(:info, "Evaluation plan created.")
         |> push_navigate(to: ~p"/admin/prospects/#{plan.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    case Integer.parse(to_string(id)) do
      {plan_id, ""} ->
        plan = Prospects.get_plan!(socket.assigns.tenant.id, plan_id)
        {:ok, _} = Prospects.delete_plan(plan)

        {:noreply,
         socket
         |> put_flash(:info, "Plan deleted.")
         |> assign(:plans, Prospects.list_plans(socket.assigns.tenant.id))}

      _invalid ->
        {:noreply, socket}
    end
  end

  defp new_form(tenant) do
    %ProspectPlan{tenant_id: tenant.id}
    |> Prospects.change_plan()
    |> to_form()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div id="prospect-plans" class="space-y-8">
        <section class="flex flex-col gap-2">
          <p class="text-[13px] font-medium text-base-content/50">{@tenant.name}</p>
          <h1 class="text-2xl font-semibold tracking-tight">Discover</h1>
          <p class="max-w-2xl text-sm leading-6 text-base-content/60">
            Capture one painful workflow from a prospect conversation and turn it into a
            demo-ready evaluation plan with a 90-day roadmap.
          </p>
        </section>

        <section class="grid gap-6 lg:grid-cols-[minmax(0,1.1fr)_minmax(0,0.9fr)]">
          <div class="rounded-lg border border-base-300 bg-base-100 p-5">
            <h2 class="text-base font-semibold">One painful workflow</h2>
            <p class="mt-1 text-sm text-base-content/60">
              Only company and workflow are required — capture the rest as it comes up.
            </p>

            <.form
              for={@form}
              id="prospect-plan-form"
              phx-change="validate"
              phx-submit="save"
              class="mt-5 space-y-4"
            >
              <div class="grid gap-4 sm:grid-cols-2">
                <.input field={@form[:company_name]} type="text" label="Company" />
                <.input field={@form[:sector]} type="text" label="Sector (optional)" />
              </div>
              <.input
                field={@form[:workflow_pain]}
                type="textarea"
                label="The workflow and why it hurts"
                placeholder="e.g. Answering reimbursement and policy questions pulls the ops lead out of deep work a dozen times a week."
              />
              <.input
                field={@form[:systems]}
                type="text"
                label="Systems involved (comma-separated, optional)"
                placeholder="Slack, Notion, Gmail, DATEV"
              />
              <.input
                field={@form[:manual_steps]}
                type="textarea"
                label="Current manual steps (one per line, optional)"
                placeholder="Look up the policy in Notion\nAsk the ops lead in Slack\nForward the answer by email"
              />
              <.input
                field={@form[:risk_notes]}
                type="textarea"
                label="Risk / compliance notes (optional)"
                placeholder="Personal data in HR docs; anything customer-facing needs sign-off."
              />
              <.input
                field={@form[:success_metric]}
                type="text"
                label="Business metric to prove (optional)"
                placeholder="Ops-lead interruptions per week"
              />

              <div class="flex justify-end">
                <button id="prospect-plan-submit" class="btn btn-primary">
                  Create evaluation plan
                </button>
              </div>
            </.form>
          </div>

          <div class="rounded-lg border border-base-300 bg-base-100">
            <div class="flex items-center justify-between border-b border-base-300 px-5 py-4">
              <h2 class="text-base font-semibold">Evaluation plans</h2>
              <span class="text-xs tabular-nums text-base-content/50">{length(@plans)}</span>
            </div>

            <div
              :if={@plans == []}
              id="prospect-plans-empty"
              class="px-5 py-10 text-sm text-base-content/60"
            >
              No plans yet. The first one takes about two minutes during a prospect call.
            </div>

            <div :if={@plans != []} class="divide-y divide-base-300/70">
              <div
                :for={plan <- @plans}
                id={"prospect-plan-#{plan.id}"}
                class="flex items-center justify-between gap-3 px-5 py-3"
              >
                <.link
                  navigate={~p"/admin/prospects/#{plan.id}"}
                  class="min-w-0 flex-1 transition-colors hover:text-base-content"
                >
                  <p class="truncate text-sm font-medium">{plan.company_name}</p>
                  <p class="mt-0.5 truncate text-xs text-base-content/55">
                    {plan.workflow_pain}
                  </p>
                </.link>
                <div class="flex shrink-0 items-center gap-1">
                  <span class="hidden font-mono text-[11px] tabular-nums text-base-content/40 sm:inline">
                    {Calendar.strftime(plan.inserted_at, "%b %d")}
                  </span>
                  <button
                    id={"delete-plan-#{plan.id}"}
                    class="btn btn-ghost btn-xs text-error"
                    phx-click="delete"
                    phx-value-id={plan.id}
                    data-confirm="Delete this evaluation plan?"
                  >
                    <.icon name="hero-trash" class="size-3.5" />
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
