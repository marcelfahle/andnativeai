defmodule AndnativeAi.Runtime.AuditEventKinds do
  @moduledoc """
  Registry for persisted runtime audit event kinds and display metadata.
  """

  @events %{
    "source_ingested" => %{label: "Source ingested", icon: "hero-arrow-down-tray", tone: :ready},
    "memory_indexed" => %{label: "Memory indexed", icon: "hero-circle-stack", tone: :ready},
    "source_deleted" => %{label: "Source deleted", icon: "hero-trash", tone: :warning},
    "source_policy_changed" => %{
      label: "Policy changed",
      icon: "hero-shield-check",
      tone: :warning
    },
    "slack_mention_received" => %{
      label: "Slack mention",
      icon: "hero-chat-bubble-left-right",
      tone: :ready
    },
    "memory_searched" => %{label: "Memory searched", icon: "hero-magnifying-glass", tone: :ready},
    "answer_generated" => %{label: "Answer generated", icon: "hero-sparkles", tone: :ready},
    "citation_attached" => %{label: "Citation attached", icon: "hero-link", tone: :ready},
    "slack_response_posted" => %{
      label: "Slack response posted",
      icon: "hero-paper-airplane",
      tone: :ready
    },
    "slack_response_failed" => %{
      label: "Slack response failed",
      icon: "hero-exclamation-triangle",
      tone: :error
    },
    "runtime_error" => %{label: "Runtime error", icon: "hero-exclamation-triangle", tone: :error}
  }

  def all, do: @events
  def keys, do: Map.keys(@events)

  def display(kind) do
    Map.get(@events, kind, %{
      label: kind |> String.replace("_", " ") |> String.capitalize(),
      icon: "hero-list-bullet",
      tone: :ready
    })
  end
end
