defmodule AndnativeAi.Runtime.OpenClaw do
  @behaviour AndnativeAi.Runtime.Adapter

  alias AndnativeAi.Memory
  alias AndnativeAi.Memory.Agent
  alias AndnativeAi.Runtime.{Audit, MemoryTool, ModelPolicy}
  alias AndnativeAi.Skills

  @impl true
  def sync_agent(%Agent{} = agent) do
    path = agent_config_path(agent)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(agent_config(agent), pretty: true))

    agent
    |> Memory.update_agent(%{runtime_ref: path, status: "synced"})
  end

  @impl true
  def dispatch_mention(%Agent{} = agent, slack_event) do
    question = question_from_event(slack_event)
    request_id = Audit.request_id_from_event(slack_event)

    case MemoryTool.call(%{tenant_id: agent.tenant_id, query: question, limit: 3}) do
      {:ok, results} ->
        record_memory_searched(agent, request_id, results)

        enabled_skills = Skills.enabled_skills(agent.id)
        selected_skill = Skills.select_for_text(enabled_skills, question)

        response =
          compose_response(agent, question, results, %{
            enabled: enabled_skills,
            selected: selected_skill
          })

        # Only claim the skill shaped the answer when the model actually
        # ran with it; deterministic fallbacks never see skill bodies.
        if selected_skill && response.status == "model" do
          Skills.record_skill_used(agent.tenant_id, agent.id, request_id, selected_skill)
        end

        record_answer_generated(agent, request_id, response, results)
        record_model_runtime_error(agent, request_id, response)
        record_citation_attached(agent, request_id, response.citations)

        {:ok,
         %{
           agent_id: agent.id,
           request_id: request_id,
           question: question,
           answer: response.answer,
           citations: response.citations,
           source_refs: source_refs(results),
           searched_memory?: true
         }}

      {:error, reason} ->
        record_runtime_error(agent, request_id, reason)
        {:error, reason}
    end
  end

  @impl true
  def health(%Agent{} = agent) do
    config_path = agent.runtime_ref || agent_config_path(agent)

    %{
      runtime: "openclaw",
      agent_id: agent.id,
      config_path: config_path,
      config_exists?: File.exists?(config_path),
      gateway_url: gateway_url()
    }
  end

  def health(_runtime) do
    %{runtime: "openclaw", gateway_url: gateway_url(), workspace_path: workspace_path()}
  end

  def agent_config(%Agent{} = agent) do
    %{
      id: "andnative-agent-#{agent.id}",
      name: agent.name,
      identity: agent.identity,
      role: agent.role,
      model: ModelPolicy.resolve(agent, :chat),
      runtime: "openclaw",
      mcp_servers: %{
        andnative_memory: %{
          transport: "http",
          url: memory_tool_url(),
          tools: [MemoryTool.schema()]
        }
      },
      instructions: [
        "Use memory_search before answering Slack questions.",
        "Never include source URLs in answers; provenance is recorded on the governance audit trail."
      ]
    }
  end

  defp compose_response(agent, question, results, skills) do
    citations = citations(results)

    {answer, status, fallback_reason, runtime_error_reason} =
      case model_response(agent, question, results, skills) do
        {:ok, text} ->
          {text, "model", nil, nil}

        {:error, {:model_error, reason}} ->
          {deterministic_response(agent, results), "fallback", reason, reason}

        {:error, reason} ->
          {deterministic_response(agent, results), "fallback", reason, nil}
      end

    %{
      answer: answer,
      citations: citations,
      status: status,
      fallback_reason: fallback_reason,
      runtime_error_reason: runtime_error_reason
    }
  end

  defp model_response(agent, question, results, skills) do
    resolved_model = model(agent)

    # Model policy decides the provider (AAI-32); a missing or placeholder
    # key short-circuits to the deterministic fallback exactly like the
    # original OpenAI path — fallback_reason metadata, no runtime_error.
    case ModelPolicy.model_client(resolved_model) do
      {:error, reason} ->
        {:error, reason}

      {:ok, client, api_key} ->
        request = %{
          api_key: api_key,
          model: resolved_model,
          instructions: model_instructions(agent) <> skills_instructions(skills),
          input: model_input(question, results),
          max_output_tokens: 240
        }

        case client.response(request) do
          {:ok, text} -> {:ok, text}
          {:error, reason} -> {:error, {:model_error, reason}}
        end
    end
  end

  defp deterministic_response(agent, []) do
    agent
    |> identity_prefix()
    |> prefix_answer("I searched memory but could not find a relevant source.")
  end

  defp deterministic_response(agent, [top | _]) do
    agent
    |> identity_prefix()
    |> prefix_answer("#{agent.name}: #{top.text}")
  end

  # Name+URL pairs for the compact Sources footer the responder appends.
  # URLs come from citation plumbing, never from the model.
  defp source_refs(results) do
    results
    |> Enum.map(&%{name: &1.source.name, url: &1.citation_url})
    |> Enum.reject(&is_nil(&1.url))
    |> Enum.uniq_by(& &1.url)
  end

  defp citations(results) do
    results
    |> Enum.map(& &1.citation_url)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp model(agent), do: ModelPolicy.resolve(agent, :chat)

  defp model_instructions(agent) do
    """
    You are #{agent.name}.

    Follow this agent identity exactly:
    #{agent.identity}

    Answer Slack questions only from governed memory in the provided context.
    If the memory context is empty or does not answer the question, say that you could not find a relevant source.
    If asked what you can do or which skills you have, list your installed skills by name and description; this does not require memory.
    Keep answers concise. Never include source URLs or a sources line in the answer; provenance is recorded separately in the governance audit trail.
    """
  end

  # Progressive disclosure per the Agent Skills spec: enabled skills
  # contribute only name+description; a skill's body loads when the request
  # names it.
  defp skills_instructions(%{enabled: []}), do: "\n\nInstalled skills: none."

  defp skills_instructions(%{enabled: enabled, selected: selected}) do
    metadata = """


    Installed skills (govern how to do specific tasks):
    #{Skills.prompt_metadata(enabled)}
    """

    case selected do
      nil ->
        metadata

      skill ->
        metadata <>
          """

          The request invokes the skill "#{skill.name}". Follow it:
          #{skill.body}
          """
    end
  end

  defp skills_instructions(_skills), do: ""

  defp model_input(question, results) do
    """
    Question:
    #{question}

    Governed memory:
    #{memory_context(results)}

    Return one Slack-ready answer.
    """
  end

  defp memory_context([]), do: "(empty)"

  # Citations are recorded on the audit trail, not handed to the model —
  # Slack answers stay clean of source URLs.
  defp memory_context(results) do
    results
    |> Enum.with_index(1)
    |> Enum.map(fn {result, index} ->
      """
      [#{index}]
      #{result.text}
      """
    end)
    |> Enum.join("\n")
  end

  defp identity_prefix(%Agent{identity: identity}) when is_binary(identity) do
    case Regex.run(
           ~r/start (?:every conversation|each conversation|every response|each response) with ["“']([^"”']+)["”']/i,
           identity
         ) do
      [_match, prefix] -> String.trim(prefix)
      _no_match -> nil
    end
  end

  defp identity_prefix(_agent), do: nil

  defp prefix_answer(nil, answer), do: answer
  defp prefix_answer("", answer), do: answer

  defp prefix_answer(prefix, answer) do
    if String.starts_with?(answer, prefix), do: answer, else: "#{prefix} #{answer}"
  end

  defp record_memory_searched(agent, request_id, results) do
    Audit.record_best_effort(%{
      tenant_id: agent.tenant_id,
      agent_id: agent.id,
      request_id: request_id,
      event_kind: "memory_searched",
      component: "memory_tool",
      actor: agent.name,
      status: "ok",
      summary: "#{agent.name} searched governed memory.",
      metadata: %{
        result_count: length(results),
        citation_count: length(citations(results))
      }
    })
  end

  defp record_answer_generated(agent, request_id, response, results) do
    metadata = %{
      generation_mode: response.status,
      result_count: length(results),
      citation_count: length(response.citations)
    }

    metadata =
      if response.fallback_reason do
        Map.put(metadata, :fallback_reason, Audit.reason_summary(response.fallback_reason))
      else
        metadata
      end

    Audit.record_best_effort(%{
      tenant_id: agent.tenant_id,
      agent_id: agent.id,
      request_id: request_id,
      event_kind: "answer_generated",
      component: "openclaw_runtime",
      actor: agent.name,
      status: response.status,
      summary: "#{agent.name} generated a Slack answer.",
      metadata: metadata
    })
  end

  defp record_citation_attached(_agent, _request_id, []), do: :ok

  defp record_citation_attached(agent, request_id, citations) do
    Audit.record_best_effort(%{
      tenant_id: agent.tenant_id,
      agent_id: agent.id,
      request_id: request_id,
      event_kind: "citation_attached",
      component: "openclaw_runtime",
      actor: agent.name,
      status: "attached",
      summary: "#{agent.name} attached governed memory citations.",
      metadata: %{citation_count: length(citations)},
      citation_url: List.first(citations)
    })
  end

  defp record_model_runtime_error(_agent, _request_id, %{runtime_error_reason: nil}), do: :ok

  defp record_model_runtime_error(agent, request_id, response) do
    Audit.record_best_effort(%{
      tenant_id: agent.tenant_id,
      agent_id: agent.id,
      request_id: request_id,
      event_kind: "runtime_error",
      component: "openclaw_runtime",
      actor: agent.name,
      status: "error",
      summary: "#{agent.name} model call failed; deterministic fallback answered.",
      metadata: %{reason: Audit.reason_summary(response.runtime_error_reason)}
    })
  end

  defp record_runtime_error(agent, request_id, reason) do
    Audit.record_best_effort(%{
      tenant_id: agent.tenant_id,
      agent_id: agent.id,
      request_id: request_id,
      event_kind: "runtime_error",
      component: "openclaw_runtime",
      actor: agent.name,
      status: "error",
      summary: "#{agent.name} runtime dispatch failed.",
      metadata: %{reason: Audit.reason_summary(reason)}
    })
  end

  defp question_from_event(%{"text" => text}) do
    text
    |> String.replace(~r/<@[^>]+>/, "")
    |> String.trim()
  end

  defp question_from_event(_event), do: ""

  defp agent_config_path(agent) do
    Path.join([workspace_path(), "agents", "agent-#{agent.id}.json"])
  end

  defp workspace_path do
    Application.get_env(:andnative_ai, :openclaw_workspace_path) ||
      System.get_env("OPENCLAW_WORKSPACE_PATH") ||
      "var/openclaw"
  end

  defp gateway_url do
    System.get_env("OPENCLAW_GATEWAY_URL", "http://localhost:4100")
  end

  defp memory_tool_url do
    System.get_env("MEMORY_TOOL_URL", "http://control-panel:4000/api/memory/search")
  end
end
