defmodule AndnativeAi.ControlPlane do
  @moduledoc """
  Builds the prospect-facing control-plane snapshot from current demo data.

  Runtime audit events are shaped like future persisted audit rows while using
  live source data where it exists and explicit demo fallbacks where it does not.
  """

  alias AndnativeAi.Memory
  alias AndnativeAi.Runtime.OpenClaw
  alias AndnativeAi.Slack.Installations

  def snapshot(tenant) do
    agents = Memory.list_agents(tenant.id)
    sources = Memory.list_sources(tenant.id)
    all_sources = Memory.list_all_sources(tenant.id)
    memory_items = Memory.list_memory_items(tenant.id)
    installations = Installations.list_installations(tenant.id)
    agent_health = Enum.map(agents, &OpenClaw.health/1)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    status_cards =
      status_cards(%{
        agents: agents,
        sources: sources,
        memory_items: memory_items,
        installations: installations,
        agent_health: agent_health
      })

    audit_events =
      all_sources
      |> audit_events(agents, memory_items, now)
      |> Enum.sort_by(&DateTime.to_unix(&1.occurred_at), :desc)
      |> Enum.take(8)

    %{
      status_cards: status_cards,
      audit_events: audit_events,
      summary: %{
        agents_count: length(agents),
        active_sources_count: length(sources),
        memory_items_count: length(memory_items),
        live_events_count: Enum.count(audit_events, &(&1.mode == :live)),
        demo_events_count: Enum.count(audit_events, &(&1.mode == :demo))
      }
    }
  end

  defp status_cards(%{
         agents: agents,
         sources: sources,
         memory_items: memory_items,
         installations: installations,
         agent_health: agent_health
       }) do
    slack_sources = Enum.filter(sources, &(&1.source_type == "slack_channel"))
    document_sources = Enum.filter(sources, &(&1.source_type == "document"))
    synced_agents = Enum.count(agent_health, & &1.config_exists?)
    paused_agents = Enum.count(agents, &paused?/1)

    [
      %{
        id: "slack-listener",
        icon: "hero-chat-bubble-left-right",
        name: "Slack listener",
        state: slack_listener_state(installations),
        tone: slack_listener_tone(installations),
        metric: "#{length(installations)} workspaces",
        detail: "#{length(slack_sources)} invited channels feeding governed memory",
        mode: card_mode(installations != [] or Installations.env_fallback_configured?())
      },
      %{
        id: "memory-service",
        icon: "hero-circle-stack",
        name: "Memory service",
        state: if(memory_items == [], do: "waiting", else: "ready"),
        tone: if(memory_items == [], do: :warning, else: :ready),
        metric: "#{length(memory_items)} chunks",
        detail: "#{length(sources)} active sources with source-scoped retention",
        mode: card_mode(memory_items != [])
      },
      %{
        id: "openclaw-runtime",
        icon: "hero-command-line",
        name: "OpenClaw runtime",
        state: runtime_state(agents, synced_agents),
        tone: runtime_tone(agents, synced_agents),
        metric: "#{synced_agents}/#{length(agents)} synced",
        detail: "Agent configs route questions through memory tools before answers",
        mode: card_mode(agents != [])
      },
      %{
        id: "document-source",
        icon: "hero-document-text",
        name: "Document source",
        state: if(document_sources == [], do: "demo fallback", else: "indexed"),
        tone: if(document_sources == [], do: :demo, else: :ready),
        metric: "#{length(document_sources)} documents",
        detail: "Markdown and text uploads become cited memory chunks",
        mode: card_mode(document_sources != [])
      },
      %{
        id: "slack-source",
        icon: "hero-bolt",
        name: "Slack source",
        state: if(slack_sources == [], do: "demo fallback", else: "live"),
        tone: if(slack_sources == [], do: :demo, else: :ready),
        metric: "#{length(slack_sources)} channels",
        detail: "Channel backfills and message events refresh source memory",
        mode: card_mode(slack_sources != [])
      },
      %{
        id: "approval",
        icon: "hero-pause-circle",
        name: "Paused approval",
        state: if(paused_agents == 0, do: "demo fallback", else: "paused"),
        tone: if(paused_agents == 0, do: :demo, else: :warning),
        metric: "#{paused_agents} waiting",
        detail: "High-risk runtime actions can stop for human approval",
        mode: card_mode(paused_agents > 0)
      }
    ]
  end

  defp audit_events(all_sources, agents, memory_items, now) do
    real_events =
      all_sources
      |> Enum.flat_map(&source_audit_events/1)
      |> Enum.concat(memory_item_audit_events(memory_items))

    demo_events = demo_audit_events(all_sources, agents, memory_items, now)

    real_events ++ demo_events
  end

  defp source_audit_events(source) do
    ingested_at = source.last_ingested_at || source.updated_at || source.inserted_at

    ingested = %{
      id: "source-ingested-#{source.id}",
      kind: "source_ingested",
      icon: icon_for_source(source.source_type),
      title: "Source ingested",
      detail: "#{source.name} entered governed memory as #{source.source_type}.",
      actor: source_actor(source.source_type),
      status: source.status,
      mode: :live,
      occurred_at: ingested_at
    }

    deleted =
      if source.deleted_at do
        [
          %{
            id: "source-deleted-#{source.id}",
            kind: "source_deleted",
            icon: "hero-trash",
            title: "Source deleted",
            detail: "#{source.name} was soft-deleted and removed from search results.",
            actor: "Control panel",
            status: "deleted",
            mode: :live,
            occurred_at: source.deleted_at
          }
        ]
      else
        []
      end

    [ingested | deleted]
  end

  defp memory_item_audit_events([]), do: []

  defp memory_item_audit_events([item | _items]) do
    [
      %{
        id: "memory-indexed-#{item.id}",
        kind: "memory_indexed",
        icon: "hero-circle-stack",
        title: "Memory indexed",
        detail: "#{item.source_type} distillation stored with #{item.visibility} visibility.",
        actor: "Memory service",
        status: item.retention_class,
        mode: :live,
        occurred_at: item.inserted_at
      }
    ]
  end

  defp demo_audit_events(all_sources, agents, memory_items, now) do
    latest_source = List.first(all_sources)
    latest_agent = List.first(agents)

    [
      %{
        id: "demo-memory-searched",
        kind: "memory_searched",
        icon: "hero-magnifying-glass",
        title: "Memory searched",
        detail: search_detail(memory_items),
        actor: runtime_actor(latest_agent),
        status: "policy checked",
        mode: :demo,
        occurred_at: DateTime.add(now, -45, :second)
      },
      %{
        id: "demo-answer-generated",
        kind: "answer_generated",
        icon: "hero-sparkles",
        title: "Answer generated",
        detail: answer_detail(latest_agent),
        actor: "OpenClaw runtime",
        status: "model call",
        mode: :demo,
        occurred_at: DateTime.add(now, -95, :second)
      },
      %{
        id: "demo-citation-attached",
        kind: "citation_attached",
        icon: "hero-link",
        title: "Citation attached",
        detail: citation_detail(latest_source),
        actor: "Runtime responder",
        status: "governed",
        mode: :demo,
        occurred_at: DateTime.add(now, -140, :second)
      },
      %{
        id: "demo-approval-paused",
        kind: "approval_paused",
        icon: "hero-pause-circle",
        title: "Approval paused",
        detail: "A sensitive operator action is held for human approval before execution.",
        actor: "Policy gate",
        status: "HITL",
        mode: :demo,
        occurred_at: DateTime.add(now, -220, :second)
      },
      %{
        id: "demo-routing-decision",
        kind: "routing_decision",
        icon: "hero-arrows-right-left",
        title: "Routing decision",
        detail: "Slack mention routed to OpenClaw with tenant memory and audit context.",
        actor: "Slack listener",
        status: "routed",
        mode: :demo,
        occurred_at: DateTime.add(now, -300, :second)
      }
    ]
  end

  defp slack_listener_state([]) do
    if Installations.env_fallback_configured?(), do: "env fallback", else: "demo fallback"
  end

  defp slack_listener_state(_installations), do: "oauth installed"

  defp slack_listener_tone([]) do
    if Installations.env_fallback_configured?(), do: :warning, else: :demo
  end

  defp slack_listener_tone(_installations), do: :ready

  defp runtime_state([], _synced_agents), do: "demo fallback"
  defp runtime_state(_agents, 0), do: "needs sync"
  defp runtime_state(_agents, _synced_agents), do: "ready"

  defp runtime_tone([], _synced_agents), do: :demo
  defp runtime_tone(_agents, 0), do: :warning
  defp runtime_tone(_agents, _synced_agents), do: :ready

  defp card_mode(true), do: :live
  defp card_mode(false), do: :demo

  defp paused?(agent) do
    status = agent.status || ""

    status
    |> String.downcase()
    |> then(&(&1 in ["paused", "approval", "awaiting_approval", "pending_approval"]))
  end

  defp icon_for_source("document"), do: "hero-document-text"
  defp icon_for_source("slack_channel"), do: "hero-chat-bubble-left-right"
  defp icon_for_source("slack_thread"), do: "hero-chat-bubble-bottom-center-text"
  defp icon_for_source(_source_type), do: "hero-circle-stack"

  defp source_actor("document"), do: "Document ingestion"
  defp source_actor("slack_channel"), do: "Slack listener"
  defp source_actor("slack_thread"), do: "Slack listener"
  defp source_actor(_source_type), do: "Source adapter"

  defp search_detail([]) do
    "Demo fallback search shows the policy-check step before any answer is produced."
  end

  defp search_detail(memory_items) do
    "Search evaluated #{length(memory_items)} active memory chunks before answering."
  end

  defp answer_detail(nil), do: "Deterministic fallback answer available until an agent is synced."

  defp answer_detail(agent) do
    "#{agent.name} generated a concise response from governed memory context."
  end

  defp citation_detail(nil) do
    "Demo fallback citation shows where Slack permalinks and document URLs attach."
  end

  defp citation_detail(source) do
    "Citation selected from #{source.name} provenance."
  end

  defp runtime_actor(nil), do: "Runtime responder"
  defp runtime_actor(agent), do: agent.name
end
