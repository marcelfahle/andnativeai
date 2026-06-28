defmodule AndnativeAi.Runtime.OpenClawTest do
  use AndnativeAi.DataCase, async: false

  alias AndnativeAi.Memory
  alias AndnativeAi.Memory.Service
  alias AndnativeAi.Runtime.Audit
  alias AndnativeAi.Runtime.OpenClaw
  alias AndnativeAi.Runtime.Responder

  defmodule FakeSlackClient do
    def post_message(_token, channel, text, thread_ts) do
      send(self(), {:posted_slack_message, channel, text, thread_ts})
      {:ok, %{"ok" => true}}
    end
  end

  defmodule FakeOpenAIClient do
    def response(request) do
      send(self(), {:openai_request, request})

      {:ok,
       "Yo! Refund approvals require support escalation.\n\nSource: https://docs.example.com/refunds"}
    end
  end

  defmodule FailingSlackClient do
    def post_message(_token, _channel, _text, _thread_ts), do: {:error, :rate_limited}
  end

  defmodule FailingOpenAIClient do
    def response(_request) do
      {:error,
       %{
         bot_token: "xoxb-secret-token",
         answer: "full generated answer",
         text: "raw Slack question",
         safe_code: :upstream_timeout
       }}
    end
  end

  defmodule FailingAdapter do
    def dispatch_mention(_agent, _slack_event) do
      {:error, %{bot_token: "xoxb-secret-token", reason: :adapter_down}}
    end
  end

  setup do
    workspace =
      Path.join(System.tmp_dir!(), "andnative-openclaw-#{System.unique_integer([:positive])}")

    previous_workspace = Application.get_env(:andnative_ai, :openclaw_workspace_path)
    previous_openai_client = Application.get_env(:andnative_ai, :openai_client)
    previous_openai_key = System.get_env("OPENAI_API_KEY")

    Application.put_env(:andnative_ai, :openclaw_workspace_path, workspace)
    Application.delete_env(:andnative_ai, :openai_client)
    System.delete_env("OPENAI_API_KEY")

    on_exit(fn ->
      if previous_workspace do
        Application.put_env(:andnative_ai, :openclaw_workspace_path, previous_workspace)
      else
        Application.delete_env(:andnative_ai, :openclaw_workspace_path)
      end

      if previous_openai_client do
        Application.put_env(:andnative_ai, :openai_client, previous_openai_client)
      else
        Application.delete_env(:andnative_ai, :openai_client)
      end

      if previous_openai_key do
        System.put_env("OPENAI_API_KEY", previous_openai_key)
      else
        System.delete_env("OPENAI_API_KEY")
      end

      File.rm_rf(workspace)
    end)

    :ok
  end

  test "sync_agent writes an OpenClaw config with memory search tool" do
    {_tenant, agent} = agent_fixture("sync")

    assert {:ok, synced_agent} = OpenClaw.sync_agent(agent)
    assert synced_agent.status == "synced"
    assert synced_agent.runtime_ref
    assert File.exists?(synced_agent.runtime_ref)

    config = synced_agent.runtime_ref |> File.read!() |> Jason.decode!()
    assert config["runtime"] == "openclaw"

    assert get_in(config, ["mcp_servers", "andnative_memory", "tools"])
           |> List.first()
           |> Map.get("name") == "memory_search"

    assert OpenClaw.health(synced_agent).config_exists?
  end

  test "dispatch_mention searches memory and returns cited answer" do
    {tenant, agent} = agent_fixture("dispatch")
    ingest_refund_memory(tenant)

    assert {:ok, response} =
             OpenClaw.dispatch_mention(agent, %{
               "type" => "app_mention",
               "text" => "<@UBOT> How do refund approvals work?"
             })

    assert response.searched_memory?
    assert response.answer =~ "Refund approvals require support escalation"
    assert [citation | _] = response.citations
    assert citation =~ "refunds"

    events = runtime_events(tenant.id, response.request_id)
    assert event_kinds(events) == ["citation_attached", "answer_generated", "memory_searched"]

    memory_event = Enum.find(events, &(&1.event_kind == "memory_searched"))
    assert memory_event.metadata["result_count"] == 1
    assert memory_event.metadata["citation_count"] == 1

    answer_event = Enum.find(events, &(&1.event_kind == "answer_generated"))
    assert answer_event.metadata["generation_mode"] == "fallback"
    refute Map.has_key?(answer_event.metadata, "question")
    refute Map.has_key?(answer_event.metadata, "answer")
  end

  test "dispatch_mention applies a start-with identity instruction without an API key" do
    {tenant, agent} =
      agent_fixture(
        "identity-fallback",
        ~s(Answer from governed memory with concise citations. Start every conversation with "Yo!")
      )

    ingest_refund_memory(tenant)

    assert {:ok, response} =
             OpenClaw.dispatch_mention(agent, %{
               "type" => "app_mention",
               "text" => "<@UBOT> How do refund approvals work?"
             })

    assert String.starts_with?(response.answer, "Yo!")
    assert response.answer =~ "Refund approvals require support escalation"
  end

  test "dispatch_mention audits empty memory search without citation event" do
    {tenant, agent} = agent_fixture("empty-memory")

    assert {:ok, response} =
             OpenClaw.dispatch_mention(agent, %{
               "type" => "app_mention",
               "text" => "<@UBOT> What is the reimbursement policy?"
             })

    assert response.answer =~ "could not find a relevant source"

    events = runtime_events(tenant.id, response.request_id)
    assert event_kinds(events) == ["answer_generated", "memory_searched"]

    memory_event = Enum.find(events, &(&1.event_kind == "memory_searched"))
    assert memory_event.metadata["result_count"] == 0
    assert memory_event.metadata["citation_count"] == 0

    answer_event = Enum.find(events, &(&1.event_kind == "answer_generated"))
    assert answer_event.metadata["result_count"] == 0
    assert answer_event.metadata["citation_count"] == 0
  end

  test "dispatch_mention sends agent identity to model-backed responder when configured" do
    System.put_env("OPENAI_API_KEY", "sk-test")
    Application.put_env(:andnative_ai, :openai_client, FakeOpenAIClient)

    {tenant, agent} =
      agent_fixture(
        "identity-model",
        ~s(Answer from governed memory with concise citations. Start every conversation with "Yo!")
      )

    ingest_refund_memory(tenant)

    assert {:ok, response} =
             OpenClaw.dispatch_mention(agent, %{
               "type" => "app_mention",
               "text" => "<@UBOT> How do refund approvals work?"
             })

    assert response.answer =~ "Yo!"
    assert response.answer =~ "https://docs.example.com/refunds"

    assert_received {:openai_request, request}
    assert request.instructions =~ agent.identity
    assert request.input =~ "How do refund approvals work?"
    assert request.input =~ "Refund approvals require support escalation"
  end

  test "dispatch_mention audits configured model failures while returning fallback answer" do
    System.put_env("OPENAI_API_KEY", "sk-test")
    Application.put_env(:andnative_ai, :openai_client, FailingOpenAIClient)

    {tenant, agent} = agent_fixture("model-failure")
    ingest_refund_memory(tenant)

    assert {:ok, response} =
             OpenClaw.dispatch_mention(agent, %{
               "type" => "app_mention",
               "text" => "<@UBOT> How do refund approvals work?"
             })

    assert response.answer =~ "Refund approvals require support escalation"

    events = runtime_events(tenant.id, response.request_id)
    assert "runtime_error" in event_kinds(events)
    assert "answer_generated" in event_kinds(events)

    runtime_error = Enum.find(events, &(&1.event_kind == "runtime_error"))
    assert runtime_error.metadata["reason"] =~ "upstream_timeout"
    refute runtime_error.metadata["reason"] =~ "xoxb-secret-token"
    refute runtime_error.metadata["reason"] =~ "full generated answer"
    refute runtime_error.metadata["reason"] =~ "raw Slack question"
  end

  test "Slack app_mention routes to responder and posts answer" do
    {tenant, agent} = agent_fixture("mention")
    ingest_refund_memory(tenant)

    assert {:ok, response} =
             AndnativeAi.Slack.Ingestion.handle_event(
               tenant.id,
               %{
                 "type" => "app_mention",
                 "channel" => "CMENTION",
                 "ts" => "1710000200.000100",
                 "text" => "<@UBOT> refund approval?"
               },
               agent: agent,
               client: FakeSlackClient,
               bot_token: "xoxb-test"
             )

    assert response.answer =~ "Source:"
    assert_received {:posted_slack_message, "CMENTION", posted_text, "1710000200.000100"}
    assert posted_text =~ "Refund approvals"

    events = runtime_events(tenant.id, response.request_id)

    assert event_kinds(events) == [
             "slack_response_posted",
             "citation_attached",
             "answer_generated",
             "memory_searched",
             "slack_mention_received"
           ]

    assert events |> Enum.map(& &1.request_id) |> Enum.uniq() == [response.request_id]

    refute Enum.any?(events, fn event ->
             event.metadata
             |> Map.values()
             |> Enum.any?(&(&1 == "xoxb-test" or &1 == "refund approval?"))
           end)
  end

  test "Slack post failure is audited without changing response success" do
    {tenant, agent} = agent_fixture("post-failure")
    ingest_refund_memory(tenant)

    assert {:ok, response} =
             AndnativeAi.Slack.Ingestion.handle_event(
               tenant.id,
               %{
                 "type" => "app_mention",
                 "channel" => "CMENTION",
                 "ts" => "1710000400.000100",
                 "text" => "<@UBOT> refund approval?"
               },
               agent: agent,
               client: FailingSlackClient,
               bot_token: "xoxb-test"
             )

    assert response.answer =~ "Source:"

    assert Enum.any?(
             runtime_events(tenant.id, response.request_id),
             &(&1.event_kind == "slack_response_failed" and
                 &1.metadata["reason"] == "rate_limited")
           )
  end

  test "responder adapter failure is audited and returned" do
    {_tenant, agent} = agent_fixture("adapter-failure")

    assert {:error, %{reason: :adapter_down}} =
             Responder.respond_to_slack(
               agent.tenant_id,
               %{
                 "type" => "app_mention",
                 "channel" => "CERROR",
                 "ts" => "1710000450.000100",
                 "text" => "<@UBOT> refund approval?"
               },
               agent: agent,
               adapter: FailingAdapter
             )

    [runtime_error] =
      agent.tenant_id
      |> Audit.list_recent_events(limit: 10)
      |> Enum.filter(&(&1.event_kind == "runtime_error"))

    assert runtime_error.request_id == "slack:CERROR:1710000450.000100"
    assert runtime_error.metadata["reason"] =~ "adapter_down"
    refute runtime_error.metadata["reason"] =~ "xoxb-secret-token"
  end

  test "missing Slack bot token is audited without changing response success" do
    {tenant, agent} = agent_fixture("missing-bot-token")
    ingest_refund_memory(tenant)

    assert {:ok, response} =
             AndnativeAi.Slack.Ingestion.handle_event(
               tenant.id,
               %{
                 "type" => "app_mention",
                 "channel" => "CMENTION",
                 "ts" => "1710000500.000100",
                 "text" => "<@UBOT> refund approval?"
               },
               agent: agent,
               client: FakeSlackClient
             )

    assert response.answer =~ "Source:"

    assert Enum.any?(
             runtime_events(tenant.id, response.request_id),
             &(&1.event_kind == "slack_response_failed" and
                 &1.metadata["reason"] == "missing_bot_token")
           )
  end

  test "Slack mentions use stable request IDs from channel and timestamp" do
    {tenant, agent} = agent_fixture("stable-request-id")
    ingest_refund_memory(tenant)

    assert {:ok, response} =
             AndnativeAi.Slack.Ingestion.handle_event(
               tenant.id,
               %{
                 "type" => "app_mention",
                 "channel" => "CSTABLE",
                 "ts" => "1710000600.000100",
                 "text" => "<@UBOT> refund approval?"
               },
               agent: agent,
               client: FakeSlackClient,
               bot_token: "xoxb-test"
             )

    assert response.request_id == "slack:CSTABLE:1710000600.000100"
  end

  test "responder ignores unmentioned messages outside owned threads" do
    {_tenant, agent} = agent_fixture("gate")

    assert {:ignored, :not_mentioned} =
             Responder.respond_to_slack(
               agent.tenant_id,
               %{
                 "type" => "message",
                 "channel" => "CGATE",
                 "ts" => "1710000300.000100",
                 "text" => "answer this without a mention"
               },
               agent: agent
             )
  end

  defp agent_fixture(slug, identity \\ "Answer from governed memory.") do
    {:ok, tenant} =
      Memory.create_tenant(%{
        name: String.upcase(slug),
        slug: "runtime-#{slug}",
        status: "active"
      })

    {:ok, agent} =
      Memory.create_agent(tenant.id, %{
        name: "Demo Agent",
        identity: identity,
        model: "gpt-4.1-mini",
        runtime: "openclaw",
        status: "active"
      })

    {tenant, agent}
  end

  defp ingest_refund_memory(tenant) do
    Service.ingest(
      tenant.id,
      %{
        source_type: "document",
        source_id: "refunds",
        name: "refunds.md",
        permalink_or_url: "https://docs.example.com/refunds"
      },
      ["Refund approvals require support escalation and manager approval."],
      %{"permalink" => "https://docs.example.com/refunds"},
      "tenant",
      "default"
    )
  end

  defp runtime_events(tenant_id, request_id) do
    tenant_id
    |> Audit.list_recent_events(limit: 20)
    |> Enum.filter(&(&1.request_id == request_id))
  end

  defp event_kinds(events), do: Enum.map(events, & &1.event_kind)
end
