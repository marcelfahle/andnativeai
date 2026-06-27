defmodule AndnativeAi.Runtime.OpenClaw do
  @behaviour AndnativeAi.Runtime.Adapter

  alias AndnativeAi.Memory
  alias AndnativeAi.Memory.Agent
  alias AndnativeAi.Runtime.MemoryTool

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
    {:ok, results} = MemoryTool.call(%{tenant_id: agent.tenant_id, query: question, limit: 3})
    response = compose_response(agent, results)

    {:ok,
     %{
       agent_id: agent.id,
       question: question,
       answer: response.answer,
       citations: response.citations,
       searched_memory?: true
     }}
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

  defp compose_response(_agent, []) do
    %{answer: "I searched memory but could not find a relevant source.", citations: []}
  end

  defp compose_response(agent, [top | _] = results) do
    citations =
      results
      |> Enum.map(& &1.citation_url)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    citation_text =
      citations
      |> Enum.take(2)
      |> Enum.join(" ")

    %{
      answer: "#{agent.name}: #{top.text}\n\nSource: #{citation_text}",
      citations: citations
    }
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
