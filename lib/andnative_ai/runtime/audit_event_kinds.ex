defmodule AndnativeAi.Runtime.AuditEventKinds do
  @moduledoc """
  Registry for persisted runtime audit event kinds, display metadata, and
  filter categories used by the control plane.
  """

  @events %{
    "source_ingested" => %{
      label: "Source ingested",
      icon: "hero-arrow-down-tray",
      tone: :ready,
      category: :memory
    },
    "memory_indexed" => %{
      label: "Memory indexed",
      icon: "hero-circle-stack",
      tone: :ready,
      category: :memory
    },
    "source_deleted" => %{
      label: "Source deleted",
      icon: "hero-trash",
      tone: :warning,
      category: :governance
    },
    "source_policy_changed" => %{
      label: "Policy changed",
      icon: "hero-shield-check",
      tone: :warning,
      category: :governance
    },
    "collection_created" => %{
      label: "Collection confirmed",
      icon: "hero-folder-plus",
      tone: :ready,
      category: :governance
    },
    "collection_deleted" => %{
      label: "Collection deleted",
      icon: "hero-folder-minus",
      tone: :warning,
      category: :governance
    },
    "slack_mention_received" => %{
      label: "Slack mention",
      icon: "hero-chat-bubble-left-right",
      tone: :ready,
      category: :runtime
    },
    "memory_searched" => %{
      label: "Memory searched",
      icon: "hero-magnifying-glass",
      tone: :ready,
      category: :runtime
    },
    "answer_generated" => %{
      label: "Answer generated",
      icon: "hero-sparkles",
      tone: :ready,
      category: :runtime
    },
    "citation_attached" => %{
      label: "Citation attached",
      icon: "hero-link",
      tone: :ready,
      category: :runtime
    },
    "slack_response_posted" => %{
      label: "Slack response posted",
      icon: "hero-paper-airplane",
      tone: :ready,
      category: :runtime
    },
    "slack_response_failed" => %{
      label: "Slack response failed",
      icon: "hero-exclamation-triangle",
      tone: :error,
      category: :errors
    },
    "runtime_error" => %{
      label: "Runtime error",
      icon: "hero-exclamation-triangle",
      tone: :error,
      category: :errors
    }
  }

  @categories [
    %{key: :memory, label: "Memory"},
    %{key: :runtime, label: "Runtime"},
    %{key: :governance, label: "Governance"},
    %{key: :errors, label: "Errors"}
  ]

  def all, do: @events
  def keys, do: Map.keys(@events)

  @doc "Ordered filter categories for the control-plane timeline."
  def categories, do: @categories

  @doc "Event kinds belonging to the given category key."
  def kinds_for_category(category) when is_atom(category) do
    for {kind, meta} <- @events, meta.category == category, do: kind
  end

  def kinds_for_category(category) when is_binary(category) do
    case Enum.find(@categories, &(Atom.to_string(&1.key) == category)) do
      nil -> []
      %{key: key} -> kinds_for_category(key)
    end
  end

  def category(kind), do: display(kind) |> Map.get(:category, :runtime)

  def display(kind) do
    Map.get(@events, kind, %{
      label: kind |> String.replace("_", " ") |> String.capitalize(),
      icon: "hero-list-bullet",
      tone: :ready,
      category: :runtime
    })
  end
end
