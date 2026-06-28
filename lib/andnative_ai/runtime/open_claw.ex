defmodule AndnativeAi.Runtime.OpenClaw do
  @behaviour AndnativeAi.Runtime.Adapter

  alias AndnativeAi.Memory
  alias AndnativeAi.Memory.Agent
  alias AndnativeAi.Runtime.{Audit, MemoryTool, OpenAIClient}

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
        response = compose_response(agent, question, results)
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
      model: agent.model,
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
        "Cite the returned Slack permalink or document URL in the answer."
      ]
    }
  end

  defp compose_response(agent, question, results) do
    citations = citations(results)

    {answer, status, fallback_reason, runtime_error_reason} =
      case model_response(agent, question, results, citations) do
        {:ok, text} ->
          {ensure_citations(text, citations), "model", nil, nil}

        {:error, {:model_error, reason}} ->
          {deterministic_response(agent, results, citations), "fallback", reason, reason}

        {:error, reason} ->
          {deterministic_response(agent, results, citations), "fallback", reason, nil}
      end

    %{
      answer: answer,
      citations: citations,
      status: status,
      fallback_reason: fallback_reason,
      runtime_error_reason: runtime_error_reason
    }
  end

  defp model_response(agent, question, results, citations) do
    api_key = System.get_env("OPENAI_API_KEY", "")

    cond do
      api_key == "" ->
        {:error, :missing_openai_api_key}

      String.contains?(api_key, "replace-me") ->
        {:error, :placeholder_openai_api_key}

      true ->
        request = %{
          api_key: api_key,
          model: model(agent),
          instructions: model_instructions(agent),
          input: model_input(question, results, citations),
          max_output_tokens: 240
        }

        case openai_client().response(request) do
          {:ok, text} -> {:ok, text}
          {:error, reason} -> {:error, {:model_error, reason}}
        end
    end
  end

  defp deterministic_response(agent, [], _citations) do
    agent
    |> identity_prefix()
    |> prefix_answer("I searched memory but could not find a relevant source.")
  end

  defp deterministic_response(agent, [top | _], citations) do
    citation_text =
      citations
      |> Enum.take(2)
      |> Enum.join(" ")

    answer = "#{agent.name}: #{top.text}\n\nSource: #{citation_text}"

    agent
    |> identity_prefix()
    |> prefix_answer(answer)
  end

  defp citations(results) do
    results
    |> Enum.map(& &1.citation_url)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp model(agent) do
    agent.model || System.get_env("OPENAI_CHAT_MODEL", "gpt-4.1-mini")
  end

  defp model_instructions(agent) do
    """
    You are #{agent.name}.

    Follow this agent identity exactly:
    #{agent.identity}

    Answer Slack questions only from governed memory in the provided context.
    If the memory context is empty or does not answer the question, say that you could not find a relevant source.
    Keep answers concise and include the provided citation URLs when using memory.
    """
  end

  defp model_input(question, results, citations) do
    """
    Question:
    #{question}

    Governed memory:
    #{memory_context(results, citations)}

    Return one Slack-ready answer.
    """
  end

  defp memory_context([], _citations), do: "(empty)"

  defp memory_context(results, citations) do
    results
    |> Enum.with_index(1)
    |> Enum.map(fn {result, index} ->
      citation = Enum.at(citations, index - 1) || result.citation_url || ""

      """
      [#{index}]
      #{result.text}
      Citation: #{citation}
      """
    end)
    |> Enum.join("\n")
  end

  defp ensure_citations(answer, []), do: answer

  defp ensure_citations(answer, citations) do
    if Enum.any?(citations, &String.contains?(answer, &1)) do
      answer
    else
      source_text = citations |> Enum.take(2) |> Enum.join(" ")
      answer <> "\n\nSource: " <> source_text
    end
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

  defp openai_client do
    Application.get_env(:andnative_ai, :openai_client, OpenAIClient)
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
