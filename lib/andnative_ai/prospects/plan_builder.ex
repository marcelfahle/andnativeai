defmodule AndnativeAi.Prospects.PlanBuilder do
  @moduledoc """
  Turns a captured prospect workflow into a deterministic evaluation plan:
  source connections, first automation, governance checkpoints, proof
  metric, and a 30/60/90-day roadmap. Rule-based on purpose — the plan is a
  conversation tool, not a model-generated proposal.
  """

  alias AndnativeAi.Prospects.ProspectPlan

  @system_connectors [
    {~w(slack), "Slack channels — invite-driven ingestion with permalink citations", :live},
    {~w(notion confluence wiki handbook sop), "Docs exported as Markdown uploads", :live},
    {~w(drive dropbox sharepoint file files), "File exports as Markdown/text uploads", :live},
    {~w(linear jira asana ticket tickets),
     "Ticketing updates via their Slack notifications (per-channel policy)", :live},
    {~w(email gmail outlook), "Email — manual export first; connector planned", :planned},
    {~w(crm hubspot salesforce pipedrive attio),
     "CRM notes — manual export first; connector planned", :planned},
    {~w(erp sap datev accounting invoice invoices),
     "Finance/ERP extracts — manual export first; connector planned", :planned}
  ]

  def build(%ProspectPlan{} = plan) do
    %{
      pain: pain(plan),
      sources: sources(plan),
      first_automation: first_automation(plan),
      governance: governance(plan),
      proof_metric: proof_metric(plan),
      roadmap: roadmap(plan)
    }
  end

  defp pain(plan) do
    %{
      workflow: plan.workflow_pain,
      manual_steps: split_lines(plan.manual_steps),
      systems: split_terms(plan.systems)
    }
  end

  defp sources(plan) do
    matched =
      plan.systems
      |> split_terms()
      |> Enum.map(&String.downcase/1)
      |> Enum.flat_map(fn term ->
        Enum.filter(@system_connectors, fn {keywords, _label, _state} ->
          Enum.any?(keywords, &String.contains?(term, &1))
        end)
      end)

    defaults = [
      {nil, "Company handbook / SOP upload — the first cited answer in minutes", :live},
      {nil, "One public Slack channel where this workflow is discussed", :live}
    ]

    (defaults ++ matched)
    |> Enum.map(fn {_keywords, label, state} -> %{label: label, state: state} end)
    |> Enum.uniq_by(& &1.label)
  end

  defp first_automation(plan) do
    steps = split_lines(plan.manual_steps)

    candidate =
      case steps do
        [first | _] -> first
        [] -> plan.workflow_pain
      end

    %{
      headline: "Governed Q&A for this workflow",
      detail:
        "Team members mention the agent in Slack and get cited answers about " <>
          "\"#{truncate(plan.workflow_pain, 90)}\" from the connected sources. " <>
          "Read-and-answer only in the evaluation phase.",
      automation_candidate:
        "First assisted step after the evaluation: drafting \"#{truncate(candidate, 90)}\" " <>
          "for human approval."
    }
  end

  defp governance(plan) do
    base = [
      "Answers must carry a citation; no citation, no claim.",
      "Source deletion propagates to retrieval immediately and is audited.",
      "Every ingestion, retrieval, answer, and policy change lands on the audit timeline.",
      "No write actions into company systems during the evaluation."
    ]

    case plan.risk_notes do
      notes when is_binary(notes) and notes != "" ->
        notes = notes |> truncate(140) |> String.trim_trailing(".")
        base ++ ["Human checkpoint before anything touching: #{notes}."]

      _ ->
        base
    end
  end

  defp proof_metric(plan) do
    case plan.success_metric do
      metric when is_binary(metric) and metric != "" ->
        %{metric: metric, note: "Agreed with the prospect; measured before vs. after."}

      _ ->
        %{
          metric: "Time from question to trusted answer for this workflow",
          note: "Default proof metric; refine with the prospect in the first call."
        }
    end
  end

  defp roadmap(_plan) do
    [
      %{
        horizon: "First 30 days",
        title: "Prove governed memory on this one workflow",
        steps: [
          "Connect the sources above and backfill history.",
          "Shadow the workflow: team asks, agent answers with citations.",
          "Record the baseline for the proof metric."
        ]
      },
      %{
        horizon: "Days 30-60",
        title: "First assisted step with approval gates",
        steps: [
          "Add the remaining channels and document sets.",
          "Introduce the automation candidate as a human-approved draft step.",
          "Review the audit timeline together; tune channel policies."
        ]
      },
      %{
        horizon: "Days 60-90",
        title: "Decide expansion on evidence",
        steps: [
          "Compare the proof metric against the baseline.",
          "Pick the second workflow from what the timeline shows people ask.",
          "Agree the governance model for write actions, if any."
        ]
      }
    ]
  end

  defp split_terms(nil), do: []

  defp split_terms(value) do
    value
    |> String.split(~r/[,;\n]/, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp split_lines(nil), do: []

  defp split_lines(value) do
    value
    |> String.split(~r/\r?\n|;/, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp truncate(text, max) do
    if String.length(text) > max, do: String.slice(text, 0, max) <> "…", else: text
  end
end
