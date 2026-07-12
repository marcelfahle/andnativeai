defmodule AndnativeAi.Runtime.AgentRoutingTest do
  use AndnativeAi.DataCase, async: false

  alias AndnativeAi.Memory
  alias AndnativeAi.Runtime.Responder

  defmodule IdentityCapturingClient do
    def post_message(_token, channel, text, thread_ts, opts) do
      send(self(), {:posted_as, opts[:username], channel, text, thread_ts})
      {:ok, %{"ok" => true}}
    end
  end

  defmodule EchoAdapter do
    def dispatch_mention(agent, slack_event) do
      send(self(), {:dispatched, agent.name, slack_event["text"]})

      {:ok,
       %{
         agent_id: agent.id,
         request_id: "req-1",
         question: slack_event["text"],
         answer: "#{agent.name} says hi.",
         citations: [],
         source_refs: [],
         searched_memory?: true
       }}
    end
  end

  setup do
    {:ok, tenant} =
      Memory.create_tenant(%{
        name: "ROUTING",
        slug: "routing-#{System.unique_integer([:positive])}",
        status: "active"
      })

    {:ok, bran} =
      Memory.create_agent(tenant.id, %{
        "name" => "Bran",
        "identity" => "Marketing copilot.",
        "role" => "marketing",
        "status" => "active"
      })

    {:ok, jack} =
      Memory.create_agent(tenant.id, %{
        "name" => "Jack",
        "identity" => "Ops copilot.",
        "role" => "ops",
        "status" => "active"
      })

    %{tenant: tenant, bran: bran, jack: jack}
  end

  defp mention(text) do
    %{
      "type" => "app_mention",
      "channel" => "CROUTE",
      "ts" => "1710001000.000100",
      "text" => text
    }
  end

  test "a leading agent name routes to that agent and is stripped", %{tenant: tenant} do
    assert {:ok, _response} =
             Responder.respond_to_slack(
               tenant.id,
               mention("<@UBOT> jack: how do refunds work?"),
               adapter: EchoAdapter,
               client: IdentityCapturingClient,
               bot_token: "xoxb-test"
             )

    assert_received {:dispatched, "Jack", question}
    assert question == "how do refunds work?"
  end

  test "matching is case-insensitive and tolerates comma addressing", %{tenant: tenant} do
    assert {:ok, _response} =
             Responder.respond_to_slack(
               tenant.id,
               mention("<@UBOT> BRAN, draft a tagline"),
               adapter: EchoAdapter,
               client: IdentityCapturingClient,
               bot_token: "xoxb-test"
             )

    assert_received {:dispatched, "Bran", "draft a tagline"}
  end

  test "no prefix falls back to the first configured agent", %{tenant: tenant} do
    assert {:ok, _response} =
             Responder.respond_to_slack(
               tenant.id,
               mention("<@UBOT> how do refunds work?"),
               adapter: EchoAdapter,
               client: IdentityCapturingClient,
               bot_token: "xoxb-test"
             )

    assert_received {:dispatched, "Bran", _question}
  end

  test "an agent name mid-sentence does not reroute", %{tenant: tenant} do
    assert {:ok, _response} =
             Responder.respond_to_slack(
               tenant.id,
               mention("<@UBOT> what did jack say about refunds?"),
               adapter: EchoAdapter,
               client: IdentityCapturingClient,
               bot_token: "xoxb-test"
             )

    assert_received {:dispatched, "Bran", _question}
  end

  test "replies post under the routed agent's display name", %{tenant: tenant} do
    assert {:ok, _response} =
             Responder.respond_to_slack(
               tenant.id,
               mention("<@UBOT> jack: status?"),
               adapter: EchoAdapter,
               client: IdentityCapturingClient,
               bot_token: "xoxb-test"
             )

    assert_received {:posted_as, "Jack", "CROUTE", text, _thread_ts}
    assert text =~ "Jack says hi."
  end

  test "name routing composes with action intents", %{tenant: tenant, jack: jack} do
    assert {:ok, %{action: action}} =
             Responder.respond_to_slack(
               tenant.id,
               mention("<@UBOT> jack: echo: ping"),
               adapter: EchoAdapter,
               client: IdentityCapturingClient,
               bot_token: "xoxb-test"
             )

    assert action.agent_id == jack.id
    assert action.kind == "echo"
  end
end
