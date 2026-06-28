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
    |> assign(:audit_events, snapshot.audit_events)
    |> assign(:summary, snapshot.summary)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div id="control-plane-dashboard" class="space-y-8">
        <section class="flex flex-col gap-3 border-b border-base-300 pb-6 md:flex-row md:items-end md:justify-between">
          <div>
            <p class="text-sm font-medium text-base-content/60">{@tenant.name}</p>
            <h1 class="text-3xl font-semibold tracking-normal">Control plane</h1>
            <p class="mt-2 max-w-3xl text-sm leading-6 text-base-content/60">
              Governed memory, Slack connectivity, runtime sync, and persisted audit evidence.
            </p>
          </div>

          <button
            id="refresh-control-plane"
            type="button"
            phx-click="refresh"
            phx-disable-with="Refreshing..."
            class="btn btn-ghost btn-sm w-fit"
          >
            <.icon name="hero-arrow-path" class="size-4" /> Refresh
          </button>
        </section>

        <section
          id="control-plane-appliance"
          class="grid gap-4 md:grid-cols-2 xl:grid-cols-4"
        >
          <.summary_card
            label="Agents"
            value={@summary.agents_count}
            detail={"#{@summary.synced_agents_count} synced"}
          />
          <.summary_card
            label="Sources"
            value={@summary.active_sources_count}
            detail="active source rows"
          />
          <.summary_card
            label="Memory"
            value={@summary.memory_items_count}
            detail="searchable chunks"
          />
          <.summary_card
            label="Audit"
            value={@summary.audit_events_count}
            detail="recent persisted events"
          />
        </section>

        <section class="space-y-3">
          <div class="flex items-center justify-between">
            <h2 class="text-base font-semibold">Operational status</h2>
            <span class="badge badge-neutral">{length(@status_cards)}</span>
          </div>

          <div
            id="control-plane-status-grid"
            class="grid gap-4 md:grid-cols-2 xl:grid-cols-3"
          >
            <.status_card :for={card <- @status_cards} card={card} />
          </div>
        </section>

        <section
          id="runtime-trust-timeline"
          class="rounded-lg border border-base-300 bg-base-100"
        >
          <div class="flex flex-col gap-3 border-b border-base-300 px-5 py-4 md:flex-row md:items-center md:justify-between">
            <div>
              <p class="text-sm font-medium text-base-content/60">{@tenant.name}</p>
              <h2 class="text-xl font-semibold tracking-normal">Runtime audit timeline</h2>
            </div>
            <span class="badge badge-neutral">{@summary.audit_events_count} live</span>
          </div>

          <div
            :if={@audit_events == []}
            id="audit-timeline-empty"
            class="px-5 py-10 text-sm text-base-content/60"
          >
            No runtime audit events yet. Ingest a source or ask the Slack app a question to create evidence.
          </div>

          <ol :if={@audit_events != []} id="audit-timeline" class="divide-y divide-base-300">
            <li
              :for={event <- @audit_events}
              id={"audit-event-#{event.id}"}
              data-audit-kind={event.kind}
              data-audit-mode="live"
              class="grid gap-4 px-5 py-4 lg:grid-cols-[10rem_minmax(0,1fr)]"
            >
              <div class="text-xs text-base-content/50">
                <time datetime={DateTime.to_iso8601(event.occurred_at)}>
                  {format_time(event.occurred_at)}
                </time>
              </div>

              <div class="min-w-0">
                <div class="flex flex-col gap-3 md:flex-row md:items-start md:justify-between">
                  <div class="flex min-w-0 items-start gap-3">
                    <span class={[
                      "grid size-9 shrink-0 place-items-center rounded border",
                      event_icon_class(event.tone)
                    ]}>
                      <.icon name={event.icon} class="size-4" />
                    </span>

                    <div class="min-w-0">
                      <div class="flex flex-wrap items-center gap-2">
                        <h3 class="font-semibold">{event.kind_label}</h3>
                        <span class={event_tone_class(event.tone)}>{event.status}</span>
                      </div>
                      <p class="mt-1 text-sm leading-6 text-base-content/70">{event.summary}</p>
                      <div class="mt-2 flex flex-wrap items-center gap-2 text-xs text-base-content/50">
                        <span>{event.actor}</span>
                        <span aria-hidden="true">|</span>
                        <span>{event.component}</span>
                        <span :if={event.request_id} class="badge badge-outline max-w-full truncate">
                          req {short_request_id(event.request_id)}
                        </span>
                        <span :if={event.source_name} class="badge badge-outline max-w-full truncate">
                          {event.source_name}
                        </span>
                      </div>
                    </div>
                  </div>

                  <.link
                    :if={event.citation_url}
                    href={event.citation_url}
                    target="_blank"
                    rel="noopener noreferrer"
                    class="btn btn-ghost btn-xs w-fit"
                  >
                    <.icon name="hero-arrow-top-right-on-square" class="size-3.5" /> Source
                  </.link>
                </div>
              </div>
            </li>
          </ol>
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :detail, :string, required: true

  defp summary_card(assigns) do
    ~H"""
    <article class="rounded-lg border border-base-300 bg-base-100 p-5">
      <p class="text-sm text-base-content/60">{@label}</p>
      <p class="mt-2 text-2xl font-semibold tracking-normal">{@value}</p>
      <p class="mt-1 text-xs text-base-content/50">{@detail}</p>
    </article>
    """
  end

  attr :card, :map, required: true

  defp status_card(assigns) do
    ~H"""
    <article
      id={"status-card-#{@card.id}"}
      data-status-mode={@card.mode}
      class="min-h-36 rounded-lg border border-base-300 bg-base-100 p-5"
    >
      <div class="flex items-start justify-between gap-3">
        <span class="grid size-9 shrink-0 place-items-center rounded border border-base-300 bg-base-200 text-base-content/70">
          <.icon name={@card.icon} class="size-4" />
        </span>
        <span class={card_tone_class(@card.tone)}>{@card.state}</span>
      </div>
      <h3 class="mt-4 text-sm font-semibold">{@card.name}</h3>
      <p class="mt-2 text-xl font-semibold tracking-normal">{@card.metric}</p>
      <p class="mt-2 text-sm leading-6 text-base-content/60">{@card.detail}</p>
    </article>
    """
  end

  defp card_tone_class(:ready), do: "badge badge-success badge-outline"
  defp card_tone_class(:warning), do: "badge badge-warning badge-outline"
  defp card_tone_class(:empty), do: "badge badge-neutral badge-outline"
  defp card_tone_class(:neutral), do: "badge badge-ghost"

  defp event_icon_class(:ready), do: "border-success/30 bg-success/10 text-success"
  defp event_icon_class(:warning), do: "border-warning/30 bg-warning/10 text-warning"
  defp event_icon_class(:error), do: "border-error/30 bg-error/10 text-error"
  defp event_icon_class(_tone), do: "border-base-300 bg-base-200 text-base-content/60"

  defp event_tone_class(:ready), do: "badge badge-success badge-outline"
  defp event_tone_class(:warning), do: "badge badge-warning badge-outline"
  defp event_tone_class(:error), do: "badge badge-error badge-outline"
  defp event_tone_class(_tone), do: "badge badge-neutral badge-outline"

  defp format_time(%DateTime{} = date_time) do
    Calendar.strftime(date_time, "%H:%M:%S UTC")
  end

  defp short_request_id(request_id) when is_binary(request_id) do
    String.slice(request_id, 0, 8)
  end
end
