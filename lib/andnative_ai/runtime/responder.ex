defmodule AndnativeAi.Runtime.Responder do
  alias AndnativeAi.Actions
  alias AndnativeAi.Actions.ActionKinds
  alias AndnativeAi.Memory
  alias AndnativeAi.Runtime.Audit
  alias AndnativeAi.Runtime.OpenClaw
  alias AndnativeAi.Slack.{Client, Installations}

  def respond_to_slack(tenant_id, slack_event, opts \\ []) do
    if mention_or_owned_thread?(slack_event, opts) do
      agent = Keyword.get(opts, :agent) || default_agent!(tenant_id)
      adapter = Keyword.get(opts, :adapter, OpenClaw)
      request_id = Audit.request_id_from_event(slack_event)
      slack_event = Map.put(slack_event, "_andnative_request_id", request_id)

      case ActionKinds.match_intent(slack_event["text"]) do
        {:ok, kind, argument} ->
          dispatch_action(tenant_id, agent, slack_event, request_id, kind, argument, opts)

        :error ->
          answer_from_memory(tenant_id, agent, adapter, slack_event, request_id, opts)
      end
    else
      {:ignored, :not_mentioned}
    end
  end

  defp answer_from_memory(tenant_id, agent, adapter, slack_event, request_id, opts) do
    record_mention_received(tenant_id, agent, slack_event, request_id)

    case adapter.dispatch_mention(agent, slack_event) do
      {:ok, response} ->
        slack_event
        |> maybe_post_response(response.answer, opts)
        |> record_post_result(tenant_id, agent, slack_event, request_id)

        {:ok, Map.put_new(response, :request_id, request_id)}

      {:error, reason} ->
        record_runtime_error(tenant_id, agent, request_id, reason)
        {:error, reason}
    end
  end

  defp dispatch_action(tenant_id, agent, slack_event, request_id, kind, argument, opts) do
    {:ok, action} =
      Actions.request_action(tenant_id, %{
        kind: kind,
        agent_id: agent.id,
        input_summary: String.slice(argument, 0, 250),
        input: %{"argument" => argument},
        request_id: request_id,
        slack_channel_id: slack_event["channel"],
        slack_thread_ts: slack_event["thread_ts"] || slack_event["ts"]
      })

    ack =
      case action.status do
        "awaiting_approval" ->
          "Got it — this action needs a human approval first. It's waiting on the control plane."

        _queued ->
          case ActionKinds.fetch(kind) do
            {:ok, %{ack: ack}} -> ack
            :error -> "On it — I'll post the result in this thread."
          end
      end

    maybe_post_response(slack_event, ack, opts)

    {:ok, %{action: action, request_id: request_id}}
  end

  defp mention_or_owned_thread?(%{"type" => "app_mention"}, _opts), do: true

  defp mention_or_owned_thread?(%{"thread_ts" => thread_ts}, opts) do
    thread_ts in Keyword.get(opts, :owned_threads, [])
  end

  defp mention_or_owned_thread?(_event, _opts), do: false

  defp default_agent!(tenant_id) do
    case Memory.list_agents(tenant_id) do
      [agent | _] -> agent
      [] -> raise "No agent configured for tenant #{tenant_id}"
    end
  end

  defp maybe_post_response(%{"channel" => channel} = event, answer, opts) do
    client = Keyword.get(opts, :client, Client)
    bot_token = Keyword.get(opts, :bot_token, "")

    if bot_token != "" and function_exported?(client, :post_message, 4) do
      thread_ts = event["thread_ts"] || event["ts"]
      client.post_message(bot_token, channel, answer, thread_ts)
    else
      skipped_post_reason(bot_token, client)
    end
  end

  defp skipped_post_reason("", _client), do: {:error, :missing_bot_token}

  defp skipped_post_reason(_bot_token, client) do
    if function_exported?(client, :post_message, 4) do
      :skipped
    else
      {:error, :unsupported_slack_client}
    end
  end

  defp record_mention_received(tenant_id, agent, slack_event, request_id) do
    Audit.record_best_effort(%{
      tenant_id: tenant_id,
      agent_id: agent.id,
      request_id: request_id,
      event_kind: "slack_mention_received",
      component: "slack_listener",
      actor: "Slack listener",
      status: "received",
      summary: "Slack mention received for #{agent.name}.",
      metadata: slack_metadata(slack_event)
    })
  end

  defp record_post_result({:ok, _payload}, tenant_id, agent, slack_event, request_id) do
    Audit.record_best_effort(%{
      tenant_id: tenant_id,
      agent_id: agent.id,
      request_id: request_id,
      event_kind: "slack_response_posted",
      component: "runtime_responder",
      actor: "Runtime responder",
      status: "posted",
      summary: "#{agent.name} response posted to Slack.",
      metadata: slack_metadata(slack_event)
    })
  end

  defp record_post_result({:error, reason}, tenant_id, agent, slack_event, request_id) do
    Audit.record_best_effort(%{
      tenant_id: tenant_id,
      agent_id: agent.id,
      request_id: request_id,
      event_kind: "slack_response_failed",
      component: "runtime_responder",
      actor: "Runtime responder",
      status: "error",
      summary: "#{agent.name} response failed to post to Slack.",
      metadata: Map.put(slack_metadata(slack_event), :reason, Audit.reason_summary(reason))
    })
  end

  defp record_post_result(:skipped, _tenant_id, _agent, _slack_event, _request_id), do: :ok

  defp record_runtime_error(tenant_id, agent, request_id, reason) do
    Audit.record_best_effort(%{
      tenant_id: tenant_id,
      agent_id: agent.id,
      request_id: request_id,
      event_kind: "runtime_error",
      component: "runtime_responder",
      actor: "Runtime responder",
      status: "error",
      summary: "#{agent.name} runtime dispatch failed.",
      metadata: %{reason: Audit.reason_summary(reason)}
    })
  end

  defp slack_metadata(event) do
    %{
      channel_id: event["channel"],
      team_id: Installations.team_id_from_payload(%{"event" => event}),
      slack_ts: event["ts"],
      thread_ts: event["thread_ts"] || event["ts"]
    }
  end
end
