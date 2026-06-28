defmodule AndnativeAiWeb.Admin.ControlPlaneLive do
  use AndnativeAiWeb, :live_view

  alias AndnativeAi.ControlPlane
  alias AndnativeAi.Memory

  @impl true
  def mount(_params, _session, socket) do
    tenant = Memory.ensure_demo_tenant!()

    {:ok,
     socket
     |> assign(:page_title, "Control Plane")
     |> assign(:tenant, tenant)
     |> reload_snapshot()}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, reload_snapshot(socket)}
  end

  defp reload_snapshot(socket) do
    snapshot = ControlPlane.snapshot(socket.assigns.tenant)

    socket
    |> assign(:status_cards, snapshot.status_cards)
    |> assign(:left_status_cards, Enum.take(snapshot.status_cards, 3))
    |> assign(:right_status_cards, Enum.drop(snapshot.status_cards, 3))
    |> assign(:audit_events, snapshot.audit_events)
    |> assign(:summary, snapshot.summary)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div id="control-plane-dashboard" class="space-y-8">
        <section
          id="control-plane-hero"
          class="overflow-hidden rounded-lg border border-slate-800 bg-slate-950 text-slate-50 shadow-sm"
        >
          <div class="border-b border-white/10 bg-white/[0.03] px-5 py-4 sm:px-7">
            <div class="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
              <div>
                <p class="text-xs font-semibold uppercase tracking-[0.18em] text-cyan-200/80">
                  Prospect control plane
                </p>
                <h1 class="mt-2 text-3xl font-semibold tracking-normal sm:text-4xl">
                  &amp;native.ai appliance
                </h1>
                <p class="mt-2 max-w-2xl text-sm leading-6 text-slate-300">
                  Governed memory, runtime routing, and approval state for SME operators.
                </p>
              </div>

              <button
                id="refresh-control-plane"
                type="button"
                phx-click="refresh"
                class="inline-flex h-10 w-fit items-center justify-center gap-2 rounded border border-cyan-300/30 px-4 text-sm font-medium text-cyan-100 transition hover:border-cyan-200 hover:bg-cyan-300/10"
              >
                <.icon name="hero-arrow-path" class="size-4" /> Refresh
              </button>
            </div>
          </div>

          <div class="grid gap-4 p-5 lg:grid-cols-[minmax(0,0.72fr)_minmax(320px,1fr)_minmax(0,0.72fr)] lg:p-7">
            <div id="control-plane-status-left" class="grid gap-4 content-start">
              <.status_card :for={card <- @left_status_cards} card={card} />
            </div>

            <div
              id="control-plane-appliance"
              class="relative min-h-[340px] overflow-hidden rounded-lg border border-cyan-300/20 bg-slate-900/80 p-5"
            >
              <div class="absolute inset-x-6 top-8 h-px bg-cyan-300/20" />
              <div class="absolute inset-y-6 left-8 w-px bg-cyan-300/20" />
              <div class="absolute inset-y-6 right-8 w-px bg-amber-300/20" />
              <div class="relative flex min-h-[300px] flex-col justify-between">
                <div class="flex items-start justify-between gap-4">
                  <div>
                    <p class="text-xs font-semibold uppercase tracking-[0.18em] text-slate-400">
                      Tenant boundary
                    </p>
                    <p class="mt-2 text-lg font-semibold">{@tenant.name}</p>
                  </div>
                  <span class="rounded border border-emerald-300/30 bg-emerald-300/10 px-2.5 py-1 text-xs font-medium text-emerald-200">
                    governed
                  </span>
                </div>

                <div class="mx-auto grid size-44 place-items-center rounded-full border border-cyan-200/30 bg-slate-950 shadow-[0_0_80px_rgba(34,211,238,0.18)]">
                  <div class="grid size-28 place-items-center rounded-lg border border-white/15 bg-white/[0.04] text-center">
                    <div>
                      <p class="text-5xl font-semibold leading-none">&amp;</p>
                      <p class="mt-2 text-xs font-semibold uppercase tracking-[0.2em] text-cyan-100">
                        native.ai
                      </p>
                    </div>
                  </div>
                </div>

                <div class="grid grid-cols-3 gap-2 text-center text-xs">
                  <div class="rounded border border-white/10 bg-white/[0.04] p-3">
                    <p class="text-slate-400">Agents</p>
                    <p class="mt-1 text-lg font-semibold">{@summary.agents_count}</p>
                  </div>
                  <div class="rounded border border-white/10 bg-white/[0.04] p-3">
                    <p class="text-slate-400">Sources</p>
                    <p class="mt-1 text-lg font-semibold">{@summary.active_sources_count}</p>
                  </div>
                  <div class="rounded border border-white/10 bg-white/[0.04] p-3">
                    <p class="text-slate-400">Chunks</p>
                    <p class="mt-1 text-lg font-semibold">{@summary.memory_items_count}</p>
                  </div>
                </div>
              </div>
            </div>

            <div id="control-plane-status-right" class="grid gap-4 content-start">
              <.status_card :for={card <- @right_status_cards} card={card} />
            </div>
          </div>
        </section>

        <section
          id="runtime-trust-timeline"
          class="rounded-lg border border-base-300 bg-base-100"
        >
          <div class="flex flex-col gap-3 border-b border-base-300 px-5 py-4 md:flex-row md:items-center md:justify-between">
            <div>
              <p class="text-sm font-medium text-base-content/60">{@tenant.name}</p>
              <h2 class="text-xl font-semibold tracking-normal">Runtime trust timeline</h2>
            </div>
            <div class="flex flex-wrap gap-2 text-xs">
              <span class="rounded border border-emerald-500/25 bg-emerald-500/10 px-2.5 py-1 font-medium text-emerald-700 dark:text-emerald-200">
                {@summary.live_events_count} live
              </span>
              <span class="rounded border border-amber-500/25 bg-amber-500/10 px-2.5 py-1 font-medium text-amber-700 dark:text-amber-200">
                {@summary.demo_events_count} demo fallback
              </span>
            </div>
          </div>

          <ol id="audit-timeline" class="divide-y divide-base-300">
            <li
              :for={event <- @audit_events}
              id={"audit-event-#{event.id}"}
              data-audit-kind={event.kind}
              data-audit-mode={event.mode}
              class="grid gap-4 px-5 py-4 md:grid-cols-[8.5rem_minmax(0,1fr)]"
            >
              <div class="text-xs text-base-content/50">
                <time datetime={DateTime.to_iso8601(event.occurred_at)}>
                  {format_time(event.occurred_at)}
                </time>
              </div>

              <div class="min-w-0">
                <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                  <div class="flex min-w-0 items-start gap-3">
                    <span class={[
                      "grid size-9 shrink-0 place-items-center rounded border",
                      event_icon_class(event.mode)
                    ]}>
                      <.icon name={event.icon} class="size-4" />
                    </span>
                    <div class="min-w-0">
                      <h3 class="font-semibold">{event.title}</h3>
                      <p class="mt-1 text-sm leading-6 text-base-content/65">{event.detail}</p>
                      <p class="mt-2 text-xs text-base-content/50">
                        {event.actor} | {event.status}
                      </p>
                    </div>
                  </div>
                  <span class={event_mode_class(event.mode)}>
                    {event_mode_label(event.mode)}
                  </span>
                </div>
              </div>
            </li>
          </ol>
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :card, :map, required: true

  defp status_card(assigns) do
    ~H"""
    <article
      id={"status-card-#{@card.id}"}
      data-status-mode={@card.mode}
      class="rounded-lg border border-white/10 bg-white/[0.045] p-4 shadow-sm transition hover:border-cyan-200/35 hover:bg-white/[0.07]"
    >
      <div class="flex items-start justify-between gap-3">
        <span class="grid size-9 shrink-0 place-items-center rounded border border-white/10 bg-slate-950/70 text-cyan-100">
          <.icon name={@card.icon} class="size-4" />
        </span>
        <span class={card_tone_class(@card.tone)}>{@card.state}</span>
      </div>
      <h2 class="mt-4 text-sm font-semibold text-slate-100">{@card.name}</h2>
      <p class="mt-2 text-2xl font-semibold tracking-normal text-white">{@card.metric}</p>
      <p class="mt-2 text-sm leading-6 text-slate-300">{@card.detail}</p>
      <p class="mt-3 text-xs font-medium uppercase tracking-[0.14em] text-slate-500">
        {event_mode_label(@card.mode)}
      </p>
    </article>
    """
  end

  defp card_tone_class(:ready) do
    "rounded border border-emerald-300/25 bg-emerald-300/10 px-2 py-1 text-xs font-medium text-emerald-200"
  end

  defp card_tone_class(:warning) do
    "rounded border border-amber-300/25 bg-amber-300/10 px-2 py-1 text-xs font-medium text-amber-200"
  end

  defp card_tone_class(:demo) do
    "rounded border border-cyan-300/25 bg-cyan-300/10 px-2 py-1 text-xs font-medium text-cyan-200"
  end

  defp event_icon_class(:live), do: "border-emerald-500/25 bg-emerald-500/10 text-emerald-600"
  defp event_icon_class(:demo), do: "border-amber-500/25 bg-amber-500/10 text-amber-600"

  defp event_mode_class(:live) do
    "w-fit shrink-0 rounded border border-emerald-500/25 bg-emerald-500/10 px-2.5 py-1 text-xs font-medium text-emerald-700 dark:text-emerald-200"
  end

  defp event_mode_class(:demo) do
    "w-fit shrink-0 rounded border border-amber-500/25 bg-amber-500/10 px-2.5 py-1 text-xs font-medium text-amber-700 dark:text-amber-200"
  end

  defp event_mode_label(:live), do: "live data"
  defp event_mode_label(:demo), do: "demo fallback"

  defp format_time(%DateTime{} = date_time) do
    Calendar.strftime(date_time, "%H:%M:%S UTC")
  end
end
