defmodule AndnativeAi.ActionsTest do
  use AndnativeAi.DataCase, async: false

  alias AndnativeAi.Actions
  alias AndnativeAi.Actions.Worker
  alias AndnativeAi.Memory
  alias AndnativeAi.Runtime.Audit
  alias AndnativeAi.Runtime.Responder

  defmodule FakeSlackClient do
    def post_message(_token, channel, text, thread_ts) do
      send(test_pid(), {:slack_message, channel, text, thread_ts})
      {:ok, %{"ok" => true}}
    end

    def upload_file(_token, channel, thread_ts, filename, content) do
      send(test_pid(), {:slack_file, channel, thread_ts, filename, content})
      {:ok, %{"ok" => true}}
    end

    defp test_pid, do: Application.fetch_env!(:andnative_ai, :test_notify_pid)
  end

  setup do
    previous_client = Application.get_env(:andnative_ai, :slack_client)
    Application.put_env(:andnative_ai, :slack_client, FakeSlackClient)
    Application.put_env(:andnative_ai, :test_notify_pid, self())

    raw_path =
      Path.join(System.tmp_dir!(), "andnative-actions-#{System.unique_integer([:positive])}")

    previous_path = Application.get_env(:andnative_ai, :raw_sources_path)
    Application.put_env(:andnative_ai, :raw_sources_path, raw_path)

    previous_token = System.get_env("SLACK_BOT_TOKEN")
    previous_user = System.get_env("SLACK_BOT_USER_ID")
    System.put_env("SLACK_BOT_TOKEN", "xoxb-test-token")
    System.put_env("SLACK_BOT_USER_ID", "UBOT")

    on_exit(fn ->
      if previous_client,
        do: Application.put_env(:andnative_ai, :slack_client, previous_client),
        else: Application.delete_env(:andnative_ai, :slack_client)

      Application.delete_env(:andnative_ai, :test_notify_pid)

      if previous_path,
        do: Application.put_env(:andnative_ai, :raw_sources_path, previous_path),
        else: Application.delete_env(:andnative_ai, :raw_sources_path)

      if previous_token,
        do: System.put_env("SLACK_BOT_TOKEN", previous_token),
        else: System.delete_env("SLACK_BOT_TOKEN")

      if previous_user,
        do: System.put_env("SLACK_BOT_USER_ID", previous_user),
        else: System.delete_env("SLACK_BOT_USER_ID")

      File.rm_rf(raw_path)
    end)

    {:ok, tenant} =
      Memory.create_tenant(%{
        name: "Actions Tenant #{System.unique_integer([:positive])}",
        slug: "actions-#{System.unique_integer([:positive])}",
        status: "active"
      })

    {:ok, agent} =
      Memory.create_agent(tenant.id, %{
        name: "Action Agent",
        identity: "Answer from governed memory.",
        model: "gpt-4.1-mini",
        runtime: "openclaw",
        status: "active"
      })

    %{tenant: tenant, agent: agent}
  end

  test "a Slack echo intent runs end to end: ack, job, delivery, audit trace", %{
    tenant: tenant,
    agent: agent
  } do
    event = %{
      "type" => "app_mention",
      "channel" => "CACT",
      "ts" => "1710000000.000100",
      "text" => "<@UBOT> echo: the governed action loop works"
    }

    assert {:ok, %{action: action}} =
             Responder.respond_to_slack(tenant.id, event,
               agent: agent,
               bot_token: "xoxb-test-token",
               client: FakeSlackClient
             )

    # Immediate threaded ack.
    assert_receive {:slack_message, "CACT", ack, "1710000000.000100"}
    assert ack =~ "On it"

    # Echo requires no approval; the job is queued. Run it.
    assert action.status == "queued"
    assert %{success: 1} = Oban.drain_queue(queue: :actions)

    # Deliverable lands in the thread: summary message + markdown file.
    assert_receive {:slack_message, "CACT", message, "1710000000.000100"}
    assert message =~ "ready"
    assert_receive {:slack_file, "CACT", "1710000000.000100", filename, content}
    assert filename =~ "action-#{action.id}"
    assert content =~ "the governed action loop works"

    # Result persisted and status completed.
    action = Actions.get_action!(tenant.id, action.id)
    assert action.status == "completed"
    assert File.exists?(action.result_path)

    # Full audit trace under one request id.
    kinds =
      tenant.id
      |> Audit.list_request_events(action.request_id)
      |> Enum.map(& &1.event_kind)

    assert "action_requested" in kinds
    assert "action_started" in kinds
    assert "action_completed" in kinds
  end

  test "approval-gated actions wait, then run on approve", %{tenant: tenant, agent: agent} do
    Application.put_env(:andnative_ai, :extra_action_kinds, %{
      "gated" => %{
        prefix: "gated:",
        handler: AndnativeAi.Actions.Handlers.Echo,
        requires_approval: true,
        label: "Gated (test)",
        ack: "Queued for approval."
      }
    })

    on_exit(fn -> Application.delete_env(:andnative_ai, :extra_action_kinds) end)

    {:ok, action} =
      Actions.request_action(tenant.id, %{
        kind: "gated",
        agent_id: agent.id,
        input_summary: "spend money on research",
        input: %{"argument" => "spend money on research"},
        request_id: "req-gated-1",
        slack_channel_id: "CACT",
        slack_thread_ts: "1710000000.000200"
      })

    assert action.status == "awaiting_approval"
    assert [%{id: pending_id}] = Actions.list_pending_approvals(tenant.id)
    assert pending_id == action.id

    # Nothing enqueued yet.
    assert %{success: 0} = Oban.drain_queue(queue: :actions)

    {:ok, approved} = Actions.approve_action(tenant.id, action.id, "marcel@example.com")
    assert approved.status == "queued"
    assert approved.approved_by == "marcel@example.com"

    assert %{success: 1} = Oban.drain_queue(queue: :actions)
    assert Actions.get_action!(tenant.id, action.id).status == "completed"

    kinds =
      tenant.id
      |> Audit.list_request_events("req-gated-1")
      |> Enum.map(& &1.event_kind)

    assert "action_approved" in kinds
  end

  test "denied actions never run", %{tenant: tenant, agent: agent} do
    Application.put_env(:andnative_ai, :extra_action_kinds, %{
      "gated" => %{
        prefix: "gated:",
        handler: AndnativeAi.Actions.Handlers.Echo,
        requires_approval: true,
        label: "Gated (test)",
        ack: "Queued for approval."
      }
    })

    on_exit(fn -> Application.delete_env(:andnative_ai, :extra_action_kinds) end)

    {:ok, action} =
      Actions.request_action(tenant.id, %{
        kind: "gated",
        agent_id: agent.id,
        input_summary: "do something outward-facing",
        request_id: "req-denied-1"
      })

    {:ok, denied} = Actions.deny_action(tenant.id, action.id, "marcel@example.com")
    assert denied.status == "denied"
    assert %{success: 0} = Oban.drain_queue(queue: :actions)
    assert Actions.list_pending_approvals(tenant.id) == []
  end

  test "handler failures mark the action failed with sanitized audit evidence", %{
    tenant: tenant,
    agent: agent
  } do
    defmodule FailingHandler do
      @behaviour AndnativeAi.Actions.Handler
      def run(_action), do: {:error, "provider exploded with token=xoxb-secret"}
    end

    Application.put_env(:andnative_ai, :extra_action_kinds, %{
      "failing" => %{
        prefix: "failing:",
        handler: FailingHandler,
        requires_approval: false,
        label: "Failing (test)",
        ack: "ok"
      }
    })

    on_exit(fn -> Application.delete_env(:andnative_ai, :extra_action_kinds) end)

    {:ok, action} =
      Actions.request_action(tenant.id, %{
        kind: "failing",
        agent_id: agent.id,
        input_summary: "will fail",
        request_id: "req-fail-1",
        slack_channel_id: "CACT",
        slack_thread_ts: "1710000000.000300"
      })

    Oban.drain_queue(queue: :actions)

    failed = Actions.get_action!(tenant.id, action.id)
    assert failed.status == "failed"
    refute failed.error =~ "xoxb-secret"

    assert_receive {:slack_message, "CACT", failure_note, _ts}
    assert failure_note =~ "didn't work"

    events = Audit.list_request_events(tenant.id, "req-fail-1")
    failed_event = Enum.find(events, &(&1.event_kind == "action_failed"))
    assert failed_event
    refute inspect(failed_event.metadata) =~ "xoxb-secret"
  end

  test "worker is a no-op for actions that are no longer runnable", %{
    tenant: tenant,
    agent: agent
  } do
    {:ok, action} =
      Actions.request_action(tenant.id, %{
        kind: "echo",
        agent_id: agent.id,
        input_summary: "already denied",
        request_id: "req-noop-1"
      })

    {:ok, _} = Actions.deny_action(tenant.id, action.id, "marcel@example.com")

    assert :ok = perform_job(Worker, %{"action_id" => action.id})
    assert Actions.get_action!(tenant.id, action.id).status == "denied"
  end

  defp perform_job(worker, args) do
    job = %Oban.Job{args: args}
    worker.perform(job)
  end
end
