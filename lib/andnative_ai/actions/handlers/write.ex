defmodule AndnativeAi.Actions.Handlers.Write do
  @moduledoc """
  `write: <task>` — drafts marketing/business copy by composing an enabled
  skill (HOW to write it) with governed memory (WHAT is true about the
  company), citing the memory it used. Approval-gated: the output is
  outward-facing.
  """

  @behaviour AndnativeAi.Actions.Handler

  alias AndnativeAi.Memory
  alias AndnativeAi.Memory.Service
  alias AndnativeAi.Runtime.OpenAIClient
  alias AndnativeAi.Skills

  @impl true
  def run(action) do
    task = action.input["argument"] || action.input_summary

    agent = action_agent(action)
    model = AndnativeAi.Runtime.ModelPolicy.resolve(agent, :write)

    skills = if action.agent_id, do: Skills.enabled_skills(action.agent_id), else: []
    skill = Skills.select_for_text(skills, task) || List.first(skills)

    if skill && action.request_id do
      Skills.record_skill_used(action.tenant_id, action.agent_id, action.request_id, skill)
    end

    context = memory_context(action.tenant_id, task)

    case draft(task, skill, context, model) do
      {:ok, draft_text} ->
        {:ok,
         %{
           title: "Draft — #{String.slice(task, 0, 60)}",
           markdown: document(task, skill, draft_text, context),
           summary: summary_line(skill, context),
           provider: "openai/#{model}",
           citations: Enum.map(context, & &1.citation_url)
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Prefer the product collection when one exists — positioning and audience
  # docs are the WHAT for marketing tasks; fall back to tenant-wide memory.
  defp memory_context(tenant_id, task) do
    product_collection =
      tenant_id
      |> Memory.list_collections()
      |> Enum.find(&(&1.kind == "product"))

    scoped =
      case product_collection do
        nil -> []
        collection -> Service.search(tenant_id, task, %{limit: 4, collection_id: collection.id})
      end

    results = if scoped == [], do: Service.search(tenant_id, task, %{limit: 4}), else: scoped

    Enum.reject(results, &is_nil(&1.citation_url))
  end

  defp draft(task, skill, context, model) do
    api_key = System.get_env("OPENAI_API_KEY", "")

    cond do
      api_key == "" or String.contains?(api_key, "replace-me") ->
        {:error, :missing_openai_api_key}

      true ->
        openai_client().response(%{
          api_key: api_key,
          model: model,
          instructions: instructions(skill),
          input: input(task, context),
          max_output_tokens: 900
        })
    end
  end

  defp openai_client do
    Application.get_env(:andnative_ai, :openai_client, OpenAIClient)
  end

  defp instructions(nil) do
    """
    You draft business copy for a small company. Ground every factual claim
    in the provided company memory; if memory does not cover something, say
    so rather than inventing it. Return clean markdown.
    """
  end

  defp instructions(skill) do
    """
    You draft business copy for a small company. Ground every factual claim
    in the provided company memory; if memory does not cover something, say
    so rather than inventing it. Return clean markdown.

    Apply the skill "#{skill.name}" exactly:
    #{skill.body}
    """
  end

  defp input(task, context) do
    memory =
      case context do
        [] ->
          "(no relevant company memory found)"

        results ->
          Enum.map_join(results, "\n\n", fn result ->
            "- #{result.text}\n  Source: #{result.citation_url}"
          end)
      end

    """
    Task:
    #{task}

    Company memory (cite what you use):
    #{memory}
    """
  end

  defp document(task, skill, draft_text, context) do
    skill_note =
      case skill do
        nil -> ""
        skill -> "**Skill:** #{skill.name} v#{skill.version}\n"
      end

    sources =
      case context do
        [] ->
          ""

        results ->
          listed =
            results
            |> Enum.with_index(1)
            |> Enum.map_join("\n", fn {result, index} ->
              "#{index}. #{result.source.name} — #{result.citation_url}"
            end)

          "\n\n## Sources\n\n" <> listed
      end

    """
    # Draft

    **Task:** #{task}
    #{skill_note}
    ---

    #{draft_text}
    """ <> sources
  end

  defp summary_line(skill, context) do
    skill_part = if skill, do: " using the #{skill.name} skill", else: ""
    "Draft written#{skill_part}, grounded in #{length(context)} cited memory sources."
  end

  defp action_agent(%{agent_id: nil}), do: nil

  defp action_agent(action) do
    AndnativeAi.Memory.get_agent!(action.tenant_id, action.agent_id)
  rescue
    Ecto.NoResultsError -> nil
  end
end
