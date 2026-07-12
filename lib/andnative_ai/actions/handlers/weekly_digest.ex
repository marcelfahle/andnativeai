defmodule AndnativeAi.Actions.Handlers.WeeklyDigest do
  @moduledoc """
  Weekly governed-memory digest: what entered memory, what the agent
  answered, and what changed policy-wise in the last seven days — pure
  database reads, no external spend.
  """

  @behaviour AndnativeAi.Actions.Handler

  import Ecto.Query

  alias AndnativeAi.Memory
  alias AndnativeAi.Repo
  alias AndnativeAi.Runtime.AuditEvent

  @impl true
  def run(action) do
    tenant_id = action.tenant_id
    since = DateTime.add(DateTime.utc_now(), -7, :day)

    kind_counts =
      AuditEvent
      |> where([event], event.tenant_id == ^tenant_id and event.occurred_at >= ^since)
      |> group_by([event], event.event_kind)
      |> select([event], {event.event_kind, count(event.id)})
      |> Repo.all()
      |> Map.new()

    new_sources = Memory.list_sources_since(tenant_id, since)

    governance =
      AuditEvent
      |> where([event], event.tenant_id == ^tenant_id and event.occurred_at >= ^since)
      |> where(
        [event],
        event.event_kind in [
          "source_deleted",
          "source_policy_changed",
          "collection_created",
          "collection_deleted",
          "skill_installed",
          "skill_enabled",
          "action_approved",
          "action_denied"
        ]
      )
      |> order_by([event], desc: event.occurred_at)
      |> limit(10)
      |> Repo.all()

    markdown = render(kind_counts, new_sources, governance)

    {:ok,
     %{
       title: "Weekly memory digest",
       markdown: markdown,
       summary:
         "#{Map.get(kind_counts, "answer_generated", 0)} questions answered, " <>
           "#{length(new_sources)} new sources, #{length(governance)} governance decisions this week.",
       provider: "internal"
     }}
  end

  defp render(kind_counts, new_sources, governance) do
    sources_section =
      case new_sources do
        [] -> "_No new sources this week._"
        sources -> Enum.map_join(sources, "\n", &"- #{&1.name} (#{&1.source_type})")
      end

    governance_section =
      case governance do
        [] -> "_No governance decisions this week._"
        events -> Enum.map_join(events, "\n", &"- #{&1.summary}")
      end

    """
    # Weekly governed memory digest

    ## The week in numbers

    - Questions answered: #{Map.get(kind_counts, "answer_generated", 0)}
    - Citations attached: #{Map.get(kind_counts, "citation_attached", 0)}
    - Memory chunks indexed: #{Map.get(kind_counts, "memory_indexed", 0)}
    - Actions completed: #{Map.get(kind_counts, "action_completed", 0)}

    ## New sources

    #{sources_section}

    ## Governance decisions

    #{governance_section}

    ---
    _Every line above is backed by audit evidence on the control plane._
    """
  end
end
