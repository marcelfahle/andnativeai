defmodule AndnativeAiWeb.Admin.ProspectPlanLive do
  use AndnativeAiWeb, :live_view

  alias AndnativeAi.Memory
  alias AndnativeAi.Prospects
  alias AndnativeAi.Prospects.PlanBuilder

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    tenant = Memory.ensure_demo_tenant!()
    plan = Prospects.get_plan!(tenant.id, String.to_integer(id))

    {:ok,
     socket
     |> assign(:page_title, "Plan · #{plan.company_name}")
     |> assign(:tenant, tenant)
     |> assign(:plan, plan)
     |> assign(:built, PlanBuilder.build(plan))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div id="prospect-plan-preview" class="mx-auto max-w-3xl space-y-10">
        <section class="space-y-3">
          <.link
            navigate={~p"/admin/prospects"}
            class="inline-flex items-center gap-1 text-sm text-base-content/55 transition-colors hover:text-base-content"
          >
            <.icon name="hero-arrow-left" class="size-3.5" /> All plans
          </.link>

          <div class="flex flex-wrap items-end justify-between gap-3">
            <div>
              <p class="text-[13px] font-medium text-base-content/50">
                Evaluation plan &middot; {Calendar.strftime(@plan.inserted_at, "%B %d, %Y")}
              </p>
              <h1 class="mt-0.5 text-2xl font-semibold tracking-tight">
                {@plan.company_name}
              </h1>
              <p :if={@plan.sector} class="mt-1 text-sm text-base-content/60">{@plan.sector}</p>
            </div>
            <span class="rounded border border-base-300 px-2 py-1 text-[11px] font-medium uppercase tracking-wide text-base-content/50">
              proposal, not a commitment
            </span>
          </div>
        </section>

        <section id="plan-pain" class="space-y-3">
          <h2 class="text-[11px] font-semibold uppercase tracking-wider text-base-content/45">
            The workflow that hurts
          </h2>
          <p class="text-lg font-medium leading-7">{@built.pain.workflow}</p>

          <div
            :if={@built.pain.manual_steps != []}
            class="rounded-lg border border-base-300 bg-base-100 p-4"
          >
            <p class="text-xs font-medium text-base-content/55">Today, by hand:</p>
            <ol class="mt-2 space-y-1.5">
              <li
                :for={{step, index} <- Enum.with_index(@built.pain.manual_steps, 1)}
                class="flex gap-2.5 text-sm leading-6 text-base-content/75"
              >
                <span class="font-mono text-xs tabular-nums text-base-content/40">{index}.</span>
                {step}
              </li>
            </ol>
          </div>
        </section>

        <section id="plan-sources" class="space-y-3">
          <h2 class="text-[11px] font-semibold uppercase tracking-wider text-base-content/45">
            Sources to connect first
          </h2>
          <ul class="space-y-1.5">
            <li
              :for={source <- @built.sources}
              class="flex items-center justify-between gap-3 rounded-lg border border-base-300 bg-base-100 px-4 py-2.5 text-sm"
            >
              <span class="text-base-content/80">{source.label}</span>
              <span
                :if={source.state == :planned}
                class="shrink-0 rounded border border-base-300 px-1.5 py-0.5 text-[10px] font-medium uppercase tracking-wide text-base-content/50"
              >
                planned
              </span>
            </li>
          </ul>
        </section>

        <section id="plan-automation" class="space-y-3">
          <h2 class="text-[11px] font-semibold uppercase tracking-wider text-base-content/45">
            First workflow
          </h2>
          <div class="rounded-lg border border-base-300 bg-base-100 p-4">
            <p class="text-sm font-semibold">{@built.first_automation.headline}</p>
            <p class="mt-1.5 text-sm leading-6 text-base-content/70">
              {@built.first_automation.detail}
            </p>
            <p class="mt-3 border-t border-base-300 pt-3 text-sm leading-6 text-base-content/60">
              {@built.first_automation.automation_candidate}
            </p>
          </div>
        </section>

        <section id="plan-governance" class="space-y-3">
          <h2 class="text-[11px] font-semibold uppercase tracking-wider text-base-content/45">
            Governance from day one
          </h2>
          <ul class="space-y-1.5">
            <li
              :for={rule <- @built.governance}
              class="flex items-start gap-2.5 text-sm leading-6 text-base-content/75"
            >
              <.icon name="hero-shield-check" class="mt-1 size-4 shrink-0 text-base-content/40" />
              {rule}
            </li>
          </ul>
        </section>

        <section id="plan-metric" class="space-y-3">
          <h2 class="text-[11px] font-semibold uppercase tracking-wider text-base-content/45">
            The number that decides
          </h2>
          <div class="rounded-lg border border-base-300 bg-base-100 p-4">
            <p class="text-sm font-semibold">{@built.proof_metric.metric}</p>
            <p class="mt-1 text-sm text-base-content/60">{@built.proof_metric.note}</p>
          </div>
        </section>

        <section id="plan-roadmap" class="space-y-3">
          <h2 class="text-[11px] font-semibold uppercase tracking-wider text-base-content/45">
            90-day roadmap
          </h2>
          <div class="space-y-3">
            <div
              :for={phase <- @built.roadmap}
              class="rounded-lg border border-base-300 bg-base-100 p-4"
            >
              <div class="flex flex-wrap items-baseline justify-between gap-2">
                <p class="text-sm font-semibold">{phase.title}</p>
                <span class="font-mono text-[11px] tabular-nums text-base-content/45">
                  {phase.horizon}
                </span>
              </div>
              <ul class="mt-2 space-y-1">
                <li
                  :for={step <- phase.steps}
                  class="flex items-start gap-2 text-sm leading-6 text-base-content/70"
                >
                  <span class="mt-2.5 size-1 shrink-0 rounded-full bg-base-content/30"></span>
                  {step}
                </li>
              </ul>
            </div>
          </div>
        </section>

        <p
          :if={@plan.risk_notes}
          class="border-t border-base-300 pt-4 text-xs leading-5 text-base-content/50"
        >
          Risk notes captured: {@plan.risk_notes}
        </p>
      </div>
    </Layouts.app>
    """
  end
end
