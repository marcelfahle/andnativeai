defmodule AndnativeAiWeb.Admin.MemoryMapLive do
  use AndnativeAiWeb, :live_view

  alias AndnativeAi.Memory
  alias AndnativeAi.Memory.Source

  @impl true
  def mount(_params, _session, socket) do
    tenant = Memory.ensure_demo_tenant!()

    {:ok,
     socket
     |> assign(:page_title, "Memory map")
     |> assign(:tenant, tenant)
     |> assign(:expanded_source_id, nil)
     |> assign(:expanded_items, [])
     |> reload_map()}
  end

  @impl true
  def handle_event("toggle-source", %{"id" => id}, socket) do
    source_id = String.to_integer(id)

    if socket.assigns.expanded_source_id == source_id do
      {:noreply,
       socket
       |> assign(:expanded_source_id, nil)
       |> assign(:expanded_items, [])}
    else
      items =
        Memory.list_all_source_memory_items(socket.assigns.tenant.id, source_id)

      {:noreply,
       socket
       |> assign(:expanded_source_id, source_id)
       |> assign(:expanded_items, items)}
    end
  end

  defp reload_map(socket) do
    tenant_id = socket.assigns.tenant.id
    sources = Memory.list_all_sources(tenant_id)
    chunk_counts = Memory.active_item_counts_by_source(tenant_id)

    groups =
      Enum.map(group_definitions(), fn definition ->
        group_sources =
          sources
          |> Enum.filter(&(&1.source_type in definition.source_types))
          |> Enum.sort_by(&{!is_nil(&1.deleted_at), &1.name})

        active = Enum.reject(group_sources, & &1.deleted_at)

        Map.merge(definition, %{
          sources: group_sources,
          active_count: length(active),
          chunk_count: active |> Enum.map(&Map.get(chunk_counts, &1.id, 0)) |> Enum.sum()
        })
      end)

    total_active_chunks = chunk_counts |> Map.values() |> Enum.sum()

    socket
    |> assign(:groups, groups)
    |> assign(:chunk_counts, chunk_counts)
    |> assign(:total_active_chunks, total_active_chunks)
    |> assign(:active_sources_count, Enum.count(sources, &is_nil(&1.deleted_at)))
    |> assign(:deleted_sources_count, Enum.count(sources, & &1.deleted_at))
  end

  defp group_definitions do
    [
      %{
        key: "slack",
        name: "Slack channels",
        icon: "hero-chat-bubble-left-right",
        description: "Invite-driven: the bot only knows channels it was invited to.",
        source_types: ["slack_channel", "slack_thread"]
      },
      %{
        key: "documents",
        name: "Documents",
        icon: "hero-document-text",
        description: "Uploaded files, chunked with heading-aware splitting.",
        source_types: ["document"]
      }
    ]
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div id="memory-map" class="space-y-10">
        <section class="flex flex-col gap-3 md:flex-row md:items-end md:justify-between">
          <div>
            <p class="text-[13px] font-medium text-base-content/50">{@tenant.name}</p>
            <h1 class="mt-0.5 text-2xl font-semibold tracking-tight">Memory map</h1>
            <p class="mt-1.5 max-w-2xl text-sm leading-6 text-base-content/60">
              What the agent is allowed to know, and where answers can come from.
              Deleting a source removes it from retrieval immediately.
            </p>
          </div>

          <div class="flex items-center gap-5 text-sm">
            <div>
              <p class="text-[11px] font-semibold uppercase tracking-wider text-base-content/45">
                In retrieval
              </p>
              <p class="mt-0.5 text-xl font-semibold tabular-nums tracking-tight">
                {@total_active_chunks}
                <span class="text-sm font-normal text-base-content/50">chunks</span>
              </p>
            </div>
            <div>
              <p class="text-[11px] font-semibold uppercase tracking-wider text-base-content/45">
                Sources
              </p>
              <p class="mt-0.5 text-xl font-semibold tabular-nums tracking-tight">
                {@active_sources_count}
                <span
                  :if={@deleted_sources_count > 0}
                  class="text-sm font-normal text-base-content/50"
                >
                  + {@deleted_sources_count} deleted
                </span>
              </p>
            </div>
          </div>
        </section>

        <section id="memory-scope-layers" class="space-y-2">
          <h2 class="text-base font-semibold">Scope layers</h2>
          <div class="grid gap-3 md:grid-cols-2">
            <div class="rounded-lg border border-base-300 bg-base-100 p-4">
              <div class="flex items-center justify-between">
                <p class="text-sm font-semibold">Company scope</p>
                <span class="inline-flex items-center gap-1.5 text-xs text-success">
                  <span class="size-1.5 rounded-full bg-success"></span> live in this PoC
                </span>
              </div>
              <p class="mt-1.5 text-sm leading-6 text-base-content/60">
                Every source below is visible to the tenant's agents. Provenance and
                deletion are enforced per source.
              </p>
            </div>
            <div class="rounded-lg border border-dashed border-base-300 bg-base-100 p-4">
              <div class="flex items-center justify-between">
                <p class="text-sm font-semibold text-base-content/70">
                  Function &amp; person scope
                </p>
                <span class="rounded border border-base-300 px-1.5 py-0.5 text-[10px] font-medium uppercase tracking-wide text-base-content/50">
                  planned
                </span>
              </div>
              <p class="mt-1.5 text-sm leading-6 text-base-content/60">
                Per-team and per-person access rules are not implemented yet. Nothing on
                this page pretends otherwise.
              </p>
            </div>
          </div>
        </section>

        <section :for={group <- @groups} id={"memory-group-#{group.key}"} class="space-y-2">
          <div class="flex flex-wrap items-baseline justify-between gap-x-6 gap-y-1">
            <div class="flex items-center gap-2">
              <.icon name={group.icon} class="size-4 text-base-content/45" />
              <h2 class="text-base font-semibold">{group.name}</h2>
              <span class="text-xs tabular-nums text-base-content/50">
                {group.active_count} active &middot; {group.chunk_count} chunks
              </span>
            </div>
            <p class="text-xs text-base-content/50">{group.description}</p>
          </div>

          <div class="overflow-hidden rounded-lg border border-base-300 bg-base-100">
            <div
              :if={group.sources == []}
              id={"memory-group-#{group.key}-empty"}
              class="px-5 py-8 text-sm text-base-content/60"
            >
              <%= if group.key == "slack" do %>
                No channels yet. Invite the bot to a public Slack channel and its history
                becomes governed memory.
              <% else %>
                No documents yet. Upload a Markdown or text file on the <.link
                  navigate={~p"/admin/sources"}
                  class="link link-hover font-medium"
                >
                  Sources page
                </.link>.
              <% end %>
            </div>

            <div :if={group.sources != []} class="divide-y divide-base-300/70">
              <div :for={source <- group.sources} id={"memory-source-#{source.id}"}>
                <button
                  type="button"
                  phx-click="toggle-source"
                  phx-value-id={source.id}
                  class="grid w-full grid-cols-[minmax(0,1fr)_auto] items-center gap-3 px-5 py-3 text-left transition-colors hover:bg-base-200/60"
                >
                  <span class="min-w-0">
                    <span class="flex flex-wrap items-baseline gap-x-2">
                      <span class={[
                        "text-sm font-medium",
                        source.deleted_at &&
                          "text-base-content/45 line-through decoration-base-content/30"
                      ]}>
                        {source.name}
                      </span>
                      <span class="truncate font-mono text-[11px] text-base-content/40">
                        {source.source_id}
                      </span>
                    </span>
                    <span class="mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-base-content/50">
                      <span
                        :if={is_nil(source.deleted_at)}
                        class="inline-flex items-center gap-1.5 text-success"
                      >
                        <span class="size-1.5 rounded-full bg-success"></span> active in retrieval
                      </span>
                      <span :if={source.deleted_at} class="inline-flex items-center gap-1.5">
                        <span class="size-1.5 rounded-full bg-base-content/25"></span>
                        deleted &mdash; excluded from retrieval
                      </span>
                      <span :if={source.last_ingested_at} class="tabular-nums">
                        ingested {Calendar.strftime(source.last_ingested_at, "%b %d, %H:%M UTC")}
                      </span>
                      <span
                        :if={Source.ingest_bot_messages?(source)}
                        class="rounded border border-base-300 px-1.5 py-0.5 text-[10px] font-medium uppercase tracking-wide text-base-content/50"
                      >
                        app posts on
                      </span>
                    </span>
                  </span>

                  <span class="flex items-center gap-3">
                    <span class="text-sm font-semibold tabular-nums">
                      {Map.get(@chunk_counts, source.id, 0)}
                      <span class="text-xs font-normal text-base-content/50">chunks</span>
                    </span>
                    <.icon
                      name={
                        if @expanded_source_id == source.id,
                          do: "hero-chevron-up",
                          else: "hero-chevron-down"
                      }
                      class="size-4 text-base-content/30"
                    />
                  </span>
                </button>

                <div
                  :if={@expanded_source_id == source.id}
                  id={"memory-source-items-#{source.id}"}
                  class="border-t border-base-300/70 bg-base-200/40 px-5 py-3"
                >
                  <p
                    :if={@expanded_items == []}
                    class="py-2 text-sm text-base-content/60"
                  >
                    No memory chunks for this source.
                  </p>

                  <ol :if={@expanded_items != []} class="space-y-2">
                    <li
                      :for={item <- @expanded_items}
                      id={"memory-item-#{item.id}"}
                      class="rounded border border-base-300 bg-base-100 px-4 py-3"
                    >
                      <p class={[
                        "text-sm leading-6",
                        (item.deleted_at && "text-base-content/40") || "text-base-content/80"
                      ]}>
                        {truncate(item.text, 220)}
                      </p>
                      <div class="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 text-[11px] text-base-content/50">
                        <span :if={item.deleted_at} class="font-medium">deleted</span>
                        <span class="tabular-nums">retention: {item.retention_class}</span>
                        <span class="tabular-nums">visibility: {item.visibility}</span>
                        <.link
                          :if={web_url(item)}
                          href={web_url(item)}
                          target="_blank"
                          rel="noopener noreferrer"
                          class="link link-hover inline-flex items-center gap-1 font-medium"
                        >
                          <.icon name="hero-link" class="size-3" /> citation
                        </.link>
                      </div>
                    </li>
                  </ol>
                </div>
              </div>
            </div>
          </div>
        </section>

        <section
          id="memory-group-connectors"
          class="rounded-lg border border-dashed border-base-300 bg-base-100 px-5 py-4"
        >
          <div class="flex flex-wrap items-center justify-between gap-2">
            <div class="flex items-center gap-2">
              <.icon name="hero-squares-plus" class="size-4 text-base-content/40" />
              <h2 class="text-sm font-semibold text-base-content/70">Future connectors</h2>
            </div>
            <span class="rounded border border-base-300 px-1.5 py-0.5 text-[10px] font-medium uppercase tracking-wide text-base-content/50">
              planned
            </span>
          </div>
          <p class="mt-1.5 max-w-2xl text-sm leading-6 text-base-content/60">
            Email, ticketing, CRM, and workflow skills would appear here as governed
            sources with the same ingest, cite, and delete contract.
          </p>
        </section>
      </div>
    </Layouts.app>
    """
  end

  defp truncate(text, max) when byte_size(text) <= max, do: text

  defp truncate(text, max) do
    String.slice(text, 0, max) <> "…"
  end

  defp web_url(item) do
    url = item.provenance["permalink"] || item.provenance["app_link"]

    case url do
      url when is_binary(url) and url != "" ->
        if String.starts_with?(url, ["http://", "https://"]), do: url

      _ ->
        nil
    end
  end
end
