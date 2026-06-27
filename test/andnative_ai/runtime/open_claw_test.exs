defmodule AndnativeAi.Runtime.OpenClawTest do
  use AndnativeAi.DataCase, async: false

  alias AndnativeAi.Memory
  alias AndnativeAi.Memory.Service
  alias AndnativeAi.Runtime.OpenClaw
  alias AndnativeAi.Runtime.Responder

  defmodule FakeSlackClient do
    def post_message(_token, channel, text, thread_ts) do
      send(self(), {:posted_slack_message, channel, text, thread_ts})
      {:ok, %{"ok" => true}}
    end
  end

  setup do
    workspace =
      Path.join(System.tmp_dir!(), "andnative-openclaw-#{System.unique_integer([:positive])}")

    previous_workspace = Application.get_env(:andnative_ai, :openclaw_workspace_path)
    Application.put_env(:andnative_ai, :openclaw_workspace_path, workspace)

    on_exit(fn ->
      if previous_workspace do
        Application.put_env(:andnative_ai, :openclaw_workspace_path, previous_workspace)
      else
        Application.delete_env(:andnative_ai, :openclaw_workspace_path)
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

  defp agent_fixture(slug) do
    {:ok, tenant} =
      Memory.create_tenant(%{
        name: String.upcase(slug),
        slug: "runtime-#{slug}",
        status: "active"
      })

    {:ok, agent} =
      Memory.create_agent(tenant.id, %{
        name: "Demo Agent",
        identity: "Answer from governed memory.",
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
end
