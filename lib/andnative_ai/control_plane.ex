defmodule AndnativeAi.ControlPlane do
  @moduledoc """
  Builds the governed-memory control-plane snapshot from current tenant state.
  """

  alias AndnativeAi.Memory
  alias AndnativeAi.Runtime.{Audit, AuditEventKinds, OpenClaw}
  alias AndnativeAi.Slack.Installations

  def snapshot(tenant) do
    agents = Memory.list_agents(tenant.id)
    source_counts = Memory.source_counts_by_type(tenant.id)
    memory_items_count = Memory.count_memory_items(tenant.id)
    installations_count = Installations.count_installations(tenant.id)
    agent_health = Enum.map(agents, &OpenClaw.health/1)

    audit_events =
      tenant.id
      |> Audit.list_recent_events(limit: 20, preload: [:source])
      |> Enum.map(&audit_event/1)

    counts = counts(source_counts, memory_items_count, installations_count)

    %{
      status_cards:
        status_cards(%{
          agents: agents,
          counts: counts,
          agent_health: agent_health,
          audit_events: audit_events
        }),
      audit_events: audit_events,
      summary: summary(agents, counts, agent_health, audit_events)
    }
  end

  defp counts(source_counts, memory_items_count, installations_count) do
    %{
      active_sources: source_counts |> Map.values() |> Enum.sum(),
      slack_sources: Map.get(source_counts, "slack_channel", 0),
      document_sources: Map.get(source_counts, "document", 0),
      memory_items: memory_items_count || 0,
      installations: installations_count || 0
    }
  end

  defp summary(agents, counts, agent_health, audit_events) do
    %{
      agents_count: length(agents),
      synced_agents_count: Enum.count(agent_health, & &1.config_exists?),
      active_sources_count: counts.active_sources,
      memory_items_count: counts.memory_items,
      audit_events_count: length(audit_events)
    }
  end

  defp status_cards(%{
         agents: agents,
         counts: counts,
         agent_health: agent_health,
         audit_events: audit_events
       }) do
    synced_agents = Enum.count(agent_health, & &1.config_exists?)
    paused_agents = Enum.count(agents, &paused?/1)

    [
      %{
        id: "slack-listener",
        icon: "hero-chat-bubble-left-right",
        name: "Slack listener",
        state: slack_listener_state(counts.installations),
        tone: slack_listener_tone(counts.installations),
        metric: "#{counts.installations} workspaces",
        detail: "#{counts.slack_sources} invited channels feeding governed memory",
        mode: card_mode(counts.installations > 0 or Installations.env_fallback_configured?())
      },
      %{
        id: "memory-service",
        icon: "hero-circle-stack",
        name: "Memory service",
        state: if(counts.memory_items == 0, do: "empty", else: "ready"),
        tone: if(counts.memory_items == 0, do: :empty, else: :ready),
        metric: "#{counts.memory_items} chunks",
        detail: "#{counts.active_sources} active sources with source-scoped retention",
        mode: card_mode(counts.memory_items > 0)
      },
      %{
        id: "openclaw-runtime",
        icon: "hero-command-line",
        name: "OpenClaw runtime",
        state: runtime_state(agents, synced_agents),
        tone: runtime_tone(agents, synced_agents),
        metric: "#{synced_agents}/#{length(agents)} synced",
        detail: "Agent configs route Slack questions through governed memory",
        mode: card_mode(agents != [])
      },
      %{
        id: "document-source",
        icon: "hero-document-text",
        name: "Documents",
        state: if(counts.document_sources == 0, do: "empty", else: "indexed"),
        tone: if(counts.document_sources == 0, do: :empty, else: :ready),
        metric: "#{counts.document_sources} documents",
        detail: "Markdown and text uploads become cited memory chunks",
        mode: card_mode(counts.document_sources > 0)
      },
      %{
        id: "runtime-activity",
        icon: "hero-list-bullet",
        name: "Runtime activity",
        state: if(audit_events == [], do: "quiet", else: "recording"),
        tone: if(audit_events == [], do: :empty, else: :ready),
        metric: "#{length(audit_events)} events",
        detail: "Recent persisted audit rows across source and answer flows",
        mode: card_mode(audit_events != [])
      },
      %{
        id: "approval",
        icon: "hero-pause-circle",
        name: "Approval gates",
        state: if(paused_agents == 0, do: "not configured", else: "paused"),
        tone: if(paused_agents == 0, do: :neutral, else: :warning),
        metric: "#{paused_agents} waiting",
        detail: "No live approval workflow is wired in this PoC yet",
        mode: if(paused_agents == 0, do: :deferred, else: :live)
      }
    ]
  end

  defp audit_event(event) do
    display = AuditEventKinds.display(event.event_kind)

    %{
      id: event.id,
      kind: event.event_kind,
      kind_label: display.label,
      icon: display.icon,
      tone: event_tone(display.tone, event.status),
      actor: event.actor,
      component: event.component,
      status: event.status,
      summary: event.summary,
      request_id: event.request_id,
      citation_url: event.citation_url,
      source_name: source_name(event),
      occurred_at: event.occurred_at
    }
  end

  defp source_name(%{source: %{name: name}}) when is_binary(name), do: name
  defp source_name(_event), do: nil

  defp slack_listener_state(0) do
    if Installations.env_fallback_configured?(), do: "env fallback", else: "disabled"
  end

  defp slack_listener_state(_installation_count), do: "oauth installed"

  defp slack_listener_tone(0) do
    if Installations.env_fallback_configured?(), do: :warning, else: :empty
  end

  defp slack_listener_tone(_installation_count), do: :ready

  defp runtime_state([], _synced_agents), do: "no agents"
  defp runtime_state(_agents, 0), do: "needs sync"
  defp runtime_state(_agents, _synced_agents), do: "ready"

  defp runtime_tone([], _synced_agents), do: :empty
  defp runtime_tone(_agents, 0), do: :warning
  defp runtime_tone(_agents, _synced_agents), do: :ready

  defp card_mode(true), do: :live
  defp card_mode(false), do: :empty

  defp paused?(agent) do
    status = agent.status || ""

    status
    |> String.downcase()
    |> then(&(&1 in ["paused", "approval", "awaiting_approval", "pending_approval"]))
  end

  defp event_tone(_default_tone, "error"), do: :error
  defp event_tone(default_tone, _status), do: default_tone
end
