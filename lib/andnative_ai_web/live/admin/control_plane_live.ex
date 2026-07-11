defmodule AndnativeAiWeb.Admin.ControlPlaneLive do
  use AndnativeAiWeb, :live_view

  alias AndnativeAi.ControlPlane
  alias AndnativeAi.Memory
  alias AndnativeAi.Runtime.Audit
  alias AndnativeAi.Runtime.AuditEventKinds

  @page_size 25

  @impl true
  def mount(_params, _session, socket) do
    tenant = Memory.ensure_demo_tenant!()

    if connected?(socket), do: Audit.subscribe(tenant.id)

    {:ok,
     socket
     |> assign(:page_title, "Control Plane")
     |> assign(:tenant, tenant)
     |> assign(:filter, "all")
     |> assign(:query, "")
     |> assign(:selected_event, nil)
     |> assign(:trace, [])
     |> reload_snapshot()
     |> reload_timeline()}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply,
     socket
     |> reload_snapshot()
     |> reload_timeline()}
  end

  def handle_event("filter", %{"category" => category}, socket) do
    {:noreply,
     socket
     |> assign(:filter, category)
     |> reload_timeline()}
  end

  def handle_event("search", %{"q" => query}, socket) do
    {:noreply,
     socket
     |> assign(:query, String.trim(query))
     |> reload_timeline()}
  end

  def handle_event("load-more", _params, socket) do
    tenant_id = socket.assigns.tenant.id

    events =
      Audit.list_events(
        tenant_id,
        preload: [:source],
        limit: @page_size,
        category: socket.assigns.filter,
        query: socket.assigns.query,
        before_id: socket.assigns.oldest_id
      )

    presented = Enum.map(events, &ControlPlane.present_event/1)

    socket =
      Enum.reduce(presented, socket, fn event, acc ->
        stream_insert(acc, :audit_events, event, at: -1)
      end)

    {:noreply,
     socket
     |> assign(:oldest_id, oldest_id(events, socket.assigns.oldest_id))
     |> assign(:has_more?, length(events) == @page_size)}
  end

  def handle_event("select-event", %{"id" => id}, socket) do
    tenant_id = socket.assigns.tenant.id
    id = if is_binary(id), do: String.to_integer(id), else: id

    case Audit.get_event(tenant_id, id, preload: [:source]) do
      nil ->
        {:noreply, socket}

      event ->
        trace =
          tenant_id
          |> Audit.list_request_events(event.request_id, preload: [:source])
          |> Enum.map(&ControlPlane.present_event/1)

        {:noreply,
         socket
         |> assign(:selected_event, ControlPlane.present_event(event))
         |> assign(:trace, trace)}
    end
  end

  def handle_event("close-inspector", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_event, nil)
     |> assign(:trace, [])}
  end

  @impl true
  def handle_info({:audit_event_recorded, event}, socket) do
    presented = ControlPlane.present_recorded_event(event)

    socket =
      socket
      |> update(:event_counts, fn counts ->
        counts
        |> Map.update(:all, 1, &(&1 + 1))
        |> Map.update(presented.category, 1, &(&1 + 1))
      end)
      |> update(:summary, &Map.update(&1, :audit_events_count, 1, fn n -> n + 1 end))

    socket =
      if visible_with_filters?(presented, socket.assigns.filter, socket.assigns.query) do
        socket
        |> assign(:timeline_empty?, false)
        |> stream_insert(:audit_events, presented, at: 0)
      else
        socket
      end

    {:noreply, socket}
  end

  defp reload_snapshot(socket) do
    snapshot = ControlPlane.snapshot(socket.assigns.tenant)

    socket
    |> assign(:status_cards, snapshot.status_cards)
    |> assign(:summary, snapshot.summary)
    |> assign(:outcomes, snapshot.outcomes)
    |> assign(:event_counts, Audit.category_counts(socket.assigns.tenant.id))
  end

  defp reload_timeline(socket) do
    tenant_id = socket.assigns.tenant.id

    events =
      Audit.list_events(
        tenant_id,
        preload: [:source],
        limit: @page_size,
        category: socket.assigns.filter,
        query: socket.assigns.query
      )

    presented = Enum.map(events, &ControlPlane.present_event/1)

    socket
    |> assign(:timeline_empty?, presented == [])
    |> assign(:oldest_id, oldest_id(events, nil))
    |> assign(:has_more?, length(events) == @page_size)
    |> stream(:audit_events, presented, reset: true)
  end

  defp oldest_id([], fallback), do: fallback
  defp oldest_id(events, _fallback), do: events |> List.last() |> Map.fetch!(:id)

  defp visible_with_filters?(event, filter, query) do
    category_match? = filter in ["all", Atom.to_string(event.category)]

    query_match? =
      query == "" or
        Enum.any?(
          [event.request_id, event.summary, event.actor, event.kind],
          fn value ->
            is_binary(value) and String.contains?(String.downcase(value), String.downcase(query))
          end
        )

    category_match? and query_match?
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div id="control-plane-dashboard" class="space-y-10">
        <section class="flex flex-col gap-3 md:flex-row md:items-end md:justify-between">
          <div>
            <p class="text-[13px] font-medium text-base-content/50">{@tenant.name}</p>
            <h1 class="mt-0.5 text-2xl font-semibold tracking-tight">Control plane</h1>
            <p class="mt-1.5 max-w-2xl text-sm leading-6 text-base-content/60">
              What the agent knows, what it just did, and who allowed it &mdash; as persisted evidence.
            </p>
          </div>

          <div class="flex items-center gap-3">
            <span
              id="control-plane-live-indicator"
              class="inline-flex items-center gap-1.5 text-xs font-medium text-base-content/60"
            >
              <span class="relative flex size-2">
                <span class="cp-live-ping absolute inline-flex h-full w-full rounded-full bg-success opacity-60">
                </span>
                <span class="relative inline-flex size-2 rounded-full bg-success"></span>
              </span>
              Live
            </span>
            <button
              id="refresh-control-plane"
              type="button"
              phx-click="refresh"
              phx-disable-with="Refreshing..."
              class="btn btn-ghost btn-sm"
            >
              <.icon name="hero-arrow-path" class="size-4" /> Refresh
            </button>
          </div>
        </section>

        <section
          id="control-plane-appliance"
          class="grid grid-cols-2 divide-base-300 overflow-hidden rounded-lg border border-base-300 bg-base-100 max-sm:divide-y sm:grid-cols-3 sm:divide-x lg:grid-cols-5"
        >
          <.appliance_stat
            label="Agents"
            value={@summary.agents_count}
            detail={"#{@summary.synced_agents_count} synced"}
          />
          <.appliance_stat
            label="Sources"
            value={@summary.active_sources_count}
            detail="active in retrieval"
          />
          <.appliance_stat
            label="Memory"
            value={@summary.memory_items_count}
            detail="searchable chunks"
          />
          <.appliance_stat
            label="Answers"
            value={@outcomes.answers_generated}
            detail={"#{@outcomes.citations_attached} citations"}
          />
          <.appliance_stat
            label="Evidence"
            value={@event_counts[:all] || 0}
            detail="persisted audit rows"
          />
        </section>

        <section id="control-plane-outcomes" class="space-y-3">
          <div class="flex flex-wrap items-baseline justify-between gap-x-6 gap-y-1">
            <h2 class="text-base font-semibold">Outcomes</h2>
            <p class="text-xs text-base-content/50">
              Real counts from this tenant; estimates are labeled.
            </p>
          </div>

          <div class="grid gap-4 lg:grid-cols-[minmax(0,1fr)_20rem]">
            <div class="grid grid-cols-2 gap-px overflow-hidden rounded-lg border border-base-300 bg-base-300 sm:grid-cols-2 xl:grid-cols-2">
              <.outcome_tile
                id="outcome-answers"
                label="Questions answered"
                value={@outcomes.answers_generated}
                detail="with governed retrieval"
              />
              <.outcome_tile
                id="outcome-citations"
                label="Answers with citations"
                value={@outcomes.citations_attached}
                detail="provenance attached"
              />
              <.outcome_tile
                id="outcome-time-saved"
                label="Time reclaimed"
                value={format_minutes(@outcomes.minutes_saved_estimate)}
                detail="4 min per answered question"
                badge="estimate"
              />
              <.outcome_tile
                id="outcome-model-cost"
                label="Model spend"
                value="—"
                detail="not yet metered in this PoC"
                badge="placeholder"
              />
            </div>

            <.link
              navigate={@outcomes.next_action.href}
              id="control-plane-next-action"
              class="group flex flex-col justify-between gap-4 rounded-lg border border-base-300 bg-base-100 p-5 transition-colors hover:border-base-content/25"
            >
              <div>
                <p class="text-[11px] font-semibold uppercase tracking-wider text-base-content/45">
                  Next step
                </p>
                <p class="mt-2 font-semibold leading-snug">{@outcomes.next_action.title}</p>
                <p class="mt-1.5 text-sm leading-6 text-base-content/60">
                  {@outcomes.next_action.detail}
                </p>
              </div>
              <span class="inline-flex items-center gap-1 text-sm font-medium text-base-content/70 transition-transform group-hover:translate-x-0.5">
                Go <.icon name="hero-arrow-right" class="size-4" />
              </span>
            </.link>
          </div>
        </section>

        <section class="space-y-3">
          <div class="flex items-center justify-between">
            <h2 class="text-base font-semibold">Operational status</h2>
            <span class="text-xs tabular-nums text-base-content/50">
              {length(@status_cards)} services
            </span>
          </div>

          <div id="control-plane-status-grid" class="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
            <.status_card :for={card <- @status_cards} card={card} />
          </div>
        </section>

        <section id="runtime-trust-timeline" class="rounded-lg border border-base-300 bg-base-100">
          <div class="flex flex-col gap-3 border-b border-base-300 px-5 py-4">
            <div class="flex flex-wrap items-center justify-between gap-3">
              <div>
                <h2 class="text-base font-semibold">Governed activity</h2>
                <p class="mt-0.5 text-sm text-base-content/60">
                  Every ingestion, retrieval, answer, and policy change &mdash; persisted as evidence.
                </p>
              </div>
              <span class="text-xs tabular-nums text-base-content/50">
                {@event_counts[:all] || 0} events recorded
              </span>
            </div>

            <div class="flex flex-wrap items-center gap-2">
              <div id="audit-filter-chips" class="flex flex-wrap items-center gap-1">
                <.filter_chip
                  category="all"
                  label="All"
                  count={@event_counts[:all] || 0}
                  active?={@filter == "all"}
                />
                <.filter_chip
                  :for={category <- AuditEventKinds.categories()}
                  category={Atom.to_string(category.key)}
                  label={category.label}
                  count={@event_counts[category.key] || 0}
                  active?={@filter == Atom.to_string(category.key)}
                />
              </div>

              <form
                id="audit-search-form"
                phx-change="search"
                phx-submit="search"
                class="ml-auto w-full sm:w-64"
              >
                <label class="input input-sm input-bordered flex w-full items-center gap-2">
                  <.icon name="hero-magnifying-glass" class="size-3.5 text-base-content/40" />
                  <input
                    type="text"
                    name="q"
                    value={@query}
                    placeholder="Filter by request id, actor, summary"
                    phx-debounce="250"
                    class="grow bg-transparent text-sm focus:outline-none"
                  />
                </label>
              </form>
            </div>
          </div>

          <div class={[
            "grid",
            @selected_event && "lg:grid-cols-[minmax(0,1fr)_minmax(20rem,24rem)]"
          ]}>
            <div class="min-w-0">
              <div
                :if={@timeline_empty? and @query == "" and @filter == "all"}
                id="audit-timeline-empty"
                class="px-5 py-14 text-center"
              >
                <div class="mx-auto grid size-10 place-items-center rounded-full border border-base-300 bg-base-200 text-base-content/50">
                  <.icon name="hero-shield-check" class="size-5" />
                </div>
                <p class="mt-3 text-sm font-medium">No evidence yet</p>
                <p class="mx-auto mt-1 max-w-sm text-sm leading-6 text-base-content/60">
                  Upload a document or ask the Slack bot a question. Every governed action
                  lands here with its provenance.
                </p>
              </div>

              <div
                :if={@timeline_empty? and (@query != "" or @filter != "all")}
                id="audit-timeline-no-match"
                class="px-5 py-14 text-center text-sm text-base-content/60"
              >
                No events match this filter.
                <button
                  type="button"
                  phx-click="filter"
                  phx-value-category="all"
                  class="link link-hover font-medium"
                >
                  Show everything
                </button>
              </div>

              <ol
                :if={!@timeline_empty?}
                id="audit-timeline"
                phx-update="stream"
                class="divide-y divide-base-300/70"
              >
                <li
                  :for={{dom_id, event} <- @streams.audit_events}
                  id={dom_id}
                  data-audit-kind={event.kind}
                  data-audit-mode="live"
                  data-audit-category={event.category}
                >
                  <button
                    type="button"
                    phx-click="select-event"
                    phx-value-id={event.id}
                    class={[
                      "cp-audit-row grid w-full grid-cols-[7rem_minmax(0,1fr)] items-baseline gap-x-3 px-5 py-2.5 text-left transition-colors hover:bg-base-200/60 sm:grid-cols-[7rem_1.25rem_minmax(0,1fr)_auto]",
                      @selected_event && @selected_event.id == event.id && "bg-base-200/80"
                    ]}
                  >
                    <time
                      datetime={DateTime.to_iso8601(event.occurred_at)}
                      class="font-mono text-[11px] tabular-nums text-base-content/45"
                    >
                      {format_time(event.occurred_at)}
                    </time>

                    <span class={["hidden sm:grid place-items-center", event_icon_text(event.tone)]}>
                      <.icon name={event.icon} class="size-3.5" />
                    </span>

                    <span class="min-w-0">
                      <span class="flex min-w-0 flex-wrap items-baseline gap-x-2">
                        <span class="text-sm font-medium">{event.kind_label}</span>
                        <span class="truncate text-sm text-base-content/60">{event.summary}</span>
                      </span>
                    </span>

                    <span class="hidden items-center gap-2 sm:flex">
                      <span
                        :if={event.status not in [nil, ""]}
                        class={["inline-flex items-center gap-1 text-[11px]", status_text(event.tone)]}
                      >
                        <span class={["size-1.5 rounded-full", status_dot(event.tone)]}></span>
                        {event.status}
                      </span>
                      <span
                        :if={event.request_id}
                        class="hidden max-w-28 truncate font-mono text-[11px] text-base-content/40 xl:inline"
                      >
                        {short_request_id(event.request_id)}
                      </span>
                      <.icon name="hero-chevron-right" class="size-3.5 text-base-content/30" />
                    </span>
                  </button>
                </li>
              </ol>

              <div
                :if={!@timeline_empty? and @has_more?}
                class="border-t border-base-300 px-5 py-3 text-center"
              >
                <button
                  id="audit-load-more"
                  type="button"
                  phx-click="load-more"
                  phx-disable-with="Loading..."
                  class="btn btn-ghost btn-xs text-base-content/60"
                >
                  Load older events
                </button>
              </div>
            </div>

            <aside
              :if={@selected_event}
              id="audit-event-inspector"
              class="border-t border-base-300 lg:border-l lg:border-t-0"
            >
              <div class="sticky top-4 max-h-[calc(100vh-2rem)] overflow-y-auto p-5">
                <div class="flex items-start justify-between gap-3">
                  <div class="flex items-center gap-2.5">
                    <span class={[
                      "grid size-8 shrink-0 place-items-center rounded border",
                      event_icon_class(@selected_event.tone)
                    ]}>
                      <.icon name={@selected_event.icon} class="size-4" />
                    </span>
                    <div>
                      <h3 class="text-sm font-semibold">{@selected_event.kind_label}</h3>
                      <p class="font-mono text-[11px] tabular-nums text-base-content/50">
                        {format_datetime(@selected_event.occurred_at)}
                      </p>
                    </div>
                  </div>
                  <button
                    id="close-audit-inspector"
                    type="button"
                    phx-click="close-inspector"
                    class="btn btn-ghost btn-xs"
                    aria-label="Close event details"
                  >
                    <.icon name="hero-x-mark" class="size-4" />
                  </button>
                </div>

                <p class="mt-3 text-sm leading-6 text-base-content/80">{@selected_event.summary}</p>

                <dl class="mt-4 space-y-2 border-t border-base-300 pt-4 text-sm">
                  <.inspector_row label="Status">
                    <span class={[
                      "inline-flex items-center gap-1.5",
                      status_text(@selected_event.tone)
                    ]}>
                      <span class={["size-1.5 rounded-full", status_dot(@selected_event.tone)]}>
                      </span>
                      {@selected_event.status}
                    </span>
                  </.inspector_row>
                  <.inspector_row label="Actor">{@selected_event.actor}</.inspector_row>
                  <.inspector_row label="Component">{@selected_event.component}</.inspector_row>
                  <.inspector_row :if={@selected_event.source_name} label="Source">
                    {@selected_event.source_name}
                  </.inspector_row>
                  <.inspector_row :if={@selected_event.request_id} label="Request">
                    <span class="break-all font-mono text-xs">{@selected_event.request_id}</span>
                  </.inspector_row>
                  <.inspector_row :if={@selected_event.citation_label} label="Citation">
                    {@selected_event.citation_label}
                  </.inspector_row>
                </dl>

                <.link
                  :if={@selected_event.citation_url}
                  href={@selected_event.citation_url}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="btn btn-outline btn-xs mt-4"
                >
                  <.icon name="hero-arrow-top-right-on-square" class="size-3.5" /> Open cited source
                </.link>

                <div :if={@selected_event.metadata != %{}} class="mt-5">
                  <p class="text-[11px] font-semibold uppercase tracking-wider text-base-content/45">
                    Evidence
                  </p>
                  <dl class="mt-2 space-y-1.5 rounded border border-base-300 bg-base-200/50 p-3">
                    <div
                      :for={{key, value} <- Enum.sort(flatten_metadata(@selected_event.metadata))}
                      class="grid grid-cols-[minmax(0,42%)_minmax(0,1fr)] gap-2"
                    >
                      <dt class="truncate font-mono text-[11px] text-base-content/50">{key}</dt>
                      <dd class="break-all font-mono text-[11px] text-base-content/80">
                        {value}
                      </dd>
                    </div>
                  </dl>
                </div>

                <div :if={length(@trace) > 1} class="mt-5">
                  <p class="text-[11px] font-semibold uppercase tracking-wider text-base-content/45">
                    Request trace &middot; {length(@trace)} steps
                  </p>
                  <ol id="audit-request-trace" class="mt-2 space-y-0.5">
                    <li :for={{step, index} <- Enum.with_index(@trace)}>
                      <button
                        type="button"
                        phx-click="select-event"
                        phx-value-id={step.id}
                        class={[
                          "grid w-full grid-cols-[1.5rem_minmax(0,1fr)_auto] items-center gap-2 rounded px-2 py-1.5 text-left text-xs transition-colors hover:bg-base-200",
                          step.id == @selected_event.id && "bg-base-200 font-medium"
                        ]}
                      >
                        <span class={["grid place-items-center", event_icon_text(step.tone)]}>
                          <.icon name={step.icon} class="size-3.5" />
                        </span>
                        <span class="truncate">{step.kind_label}</span>
                        <span class="font-mono text-[10px] tabular-nums text-base-content/40">
                          {trace_offset(@trace, index)}
                        </span>
                      </button>
                    </li>
                  </ol>
                </div>

                <p class="mt-5 border-t border-base-300 pt-3 text-[11px] leading-5 text-base-content/45">
                  Evidence is minimized: ids, counts, statuses, and citations &mdash; never tokens,
                  raw questions, or answer bodies.
                </p>
              </div>
            </aside>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :detail, :string, required: true

  defp appliance_stat(assigns) do
    ~H"""
    <div class="px-5 py-4">
      <p class="text-[11px] font-semibold uppercase tracking-wider text-base-content/45">
        {@label}
      </p>
      <p class="mt-1 text-2xl font-semibold tabular-nums tracking-tight">{@value}</p>
      <p class="mt-0.5 text-xs text-base-content/50">{@detail}</p>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :detail, :string, required: true
  attr :badge, :string, default: nil

  defp outcome_tile(assigns) do
    ~H"""
    <div id={@id} class="bg-base-100 px-5 py-4">
      <div class="flex items-center justify-between gap-2">
        <p class="text-[11px] font-semibold uppercase tracking-wider text-base-content/45">
          {@label}
        </p>
        <span
          :if={@badge}
          class="rounded border border-base-300 px-1.5 py-0.5 text-[10px] font-medium uppercase tracking-wide text-base-content/50"
        >
          {@badge}
        </span>
      </div>
      <p class="mt-1 text-2xl font-semibold tabular-nums tracking-tight">{@value}</p>
      <p class="mt-0.5 text-xs text-base-content/50">{@detail}</p>
    </div>
    """
  end

  attr :category, :string, required: true
  attr :label, :string, required: true
  attr :count, :integer, required: true
  attr :active?, :boolean, required: true

  defp filter_chip(assigns) do
    ~H"""
    <button
      type="button"
      id={"audit-filter-#{@category}"}
      phx-click="filter"
      phx-value-category={@category}
      aria-pressed={to_string(@active?)}
      class={[
        "inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-xs font-medium transition-colors",
        @active? && "border-base-content/70 bg-base-content text-base-100",
        !@active? &&
          "border-base-300 bg-base-100 text-base-content/60 hover:border-base-content/30 hover:text-base-content"
      ]}
    >
      {@label}
      <span class={[
        "tabular-nums",
        (@active? && "text-base-100/70") || "text-base-content/40"
      ]}>
        {@count}
      </span>
    </button>
    """
  end

  slot :inner_block, required: true
  attr :label, :string, required: true

  defp inspector_row(assigns) do
    ~H"""
    <div class="grid grid-cols-[6rem_minmax(0,1fr)] gap-2">
      <dt class="text-base-content/50">{@label}</dt>
      <dd class="min-w-0 text-base-content/80">{render_slot(@inner_block)}</dd>
    </div>
    """
  end

  attr :card, :map, required: true

  defp status_card(assigns) do
    ~H"""
    <article
      id={"status-card-#{@card.id}"}
      data-status-mode={@card.mode}
      class="rounded-lg border border-base-300 bg-base-100 p-4"
    >
      <div class="flex items-center justify-between gap-3">
        <div class="flex items-center gap-2.5">
          <span class="grid size-8 shrink-0 place-items-center rounded border border-base-300 bg-base-200 text-base-content/60">
            <.icon name={@card.icon} class="size-4" />
          </span>
          <h3 class="text-sm font-semibold">{@card.name}</h3>
        </div>
        <span class={["inline-flex items-center gap-1.5 text-xs", status_text(@card.tone)]}>
          <span class={["size-1.5 rounded-full", status_dot(@card.tone)]}></span>
          {@card.state}
        </span>
      </div>
      <p class="mt-3 text-lg font-semibold tabular-nums tracking-tight">{@card.metric}</p>
      <p class="mt-1 text-sm leading-6 text-base-content/60">{@card.detail}</p>
    </article>
    """
  end

  defp status_dot(:ready), do: "bg-success"
  defp status_dot(:warning), do: "bg-warning"
  defp status_dot(:error), do: "bg-error"
  defp status_dot(:empty), do: "bg-base-content/25"
  defp status_dot(_tone), do: "bg-base-content/25"

  defp status_text(:ready), do: "text-success"
  defp status_text(:warning), do: "text-warning"
  defp status_text(:error), do: "text-error"
  defp status_text(_tone), do: "text-base-content/50"

  defp event_icon_class(:ready), do: "border-success/30 bg-success/10 text-success"
  defp event_icon_class(:warning), do: "border-warning/30 bg-warning/10 text-warning"
  defp event_icon_class(:error), do: "border-error/30 bg-error/10 text-error"
  defp event_icon_class(_tone), do: "border-base-300 bg-base-200 text-base-content/60"

  defp event_icon_text(:ready), do: "text-base-content/45"
  defp event_icon_text(:warning), do: "text-warning"
  defp event_icon_text(:error), do: "text-error"
  defp event_icon_text(_tone), do: "text-base-content/45"

  defp format_time(%DateTime{} = date_time) do
    Calendar.strftime(date_time, "%H:%M:%S")
  end

  defp format_datetime(%DateTime{} = date_time) do
    Calendar.strftime(date_time, "%b %d, %Y %H:%M:%S UTC")
  end

  defp format_minutes(minutes) when minutes >= 60 do
    hours = div(minutes, 60)
    rest = rem(minutes, 60)
    if rest == 0, do: "#{hours}h", else: "#{hours}h #{rest}m"
  end

  defp format_minutes(minutes), do: "#{minutes}m"

  defp short_request_id(request_id) when is_binary(request_id) do
    String.slice(request_id, 0, 18)
  end

  defp trace_offset(trace, 0) when length(trace) > 0, do: "start"

  defp trace_offset(trace, index) do
    first = List.first(trace)
    step = Enum.at(trace, index)
    diff = DateTime.diff(step.occurred_at, first.occurred_at, :millisecond)

    cond do
      diff <= 0 -> "+0ms"
      diff < 1_000 -> "+#{diff}ms"
      diff < 60_000 -> "+#{Float.round(diff / 1_000, 1)}s"
      true -> "+#{div(diff, 60_000)}m"
    end
  end

  defp flatten_metadata(metadata, prefix \\ nil) do
    Enum.flat_map(metadata, fn {key, value} ->
      full_key = if prefix, do: "#{prefix}.#{key}", else: to_string(key)

      case value do
        %{} = nested when map_size(nested) > 0 -> flatten_metadata(nested, full_key)
        %{} -> [{full_key, "{}"}]
        list when is_list(list) -> [{full_key, inspect(list)}]
        other -> [{full_key, to_string(other)}]
      end
    end)
  end
end
