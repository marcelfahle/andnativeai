defmodule AndnativeAi.WritingActionsTest do
  use AndnativeAi.DataCase, async: false

  alias AndnativeAi.Actions
  alias AndnativeAi.Actions.DigestScheduler
  alias AndnativeAi.Memory
  alias AndnativeAi.Memory.Service
  alias AndnativeAi.Runtime.Audit
  alias AndnativeAi.Skills

  defmodule FakeOpenAI do
    def response(request) do
      send(Application.fetch_env!(:andnative_ai, :test_notify_pid), {:openai_request, request})

      {:ok,
       "subject: fewer tools, calmer ops\n\nHi — saw you ship weekly. We govern the memory behind it."}
    end
  end

  defmodule FakeSlackClient do
    def post_message(_token, channel, text, thread_ts) do
      send(
        Application.fetch_env!(:andnative_ai, :test_notify_pid),
        {:slack_message, channel, text, thread_ts}
      )

      {:ok, %{"ok" => true}}
    end

    def upload_file(_token, channel, thread_ts, filename, content) do
      send(
        Application.fetch_env!(:andnative_ai, :test_notify_pid),
        {:slack_file, channel, thread_ts, filename, content}
      )

      {:ok, %{"ok" => true}}
    end
  end

  setup do
    Application.put_env(:andnative_ai, :test_notify_pid, self())
    Application.put_env(:andnative_ai, :openai_client, FakeOpenAI)
    Application.put_env(:andnative_ai, :slack_client, FakeSlackClient)

    raw_path =
      Path.join(System.tmp_dir!(), "andnative-writing-#{System.unique_integer([:positive])}")

    previous_path = Application.get_env(:andnative_ai, :raw_sources_path)
    Application.put_env(:andnative_ai, :raw_sources_path, raw_path)

    previous_key = System.get_env("OPENAI_API_KEY")
    System.put_env("OPENAI_API_KEY", "sk-test-key")
    System.put_env("SLACK_BOT_TOKEN", "xoxb-test-token")
    System.put_env("SLACK_BOT_USER_ID", "UBOT")

    on_exit(fn ->
      Application.delete_env(:andnative_ai, :test_notify_pid)
      Application.delete_env(:andnative_ai, :openai_client)
      Application.delete_env(:andnative_ai, :slack_client)

      if previous_path,
        do: Application.put_env(:andnative_ai, :raw_sources_path, previous_path),
        else: Application.delete_env(:andnative_ai, :raw_sources_path)

      if previous_key,
        do: System.put_env("OPENAI_API_KEY", previous_key),
        else: System.delete_env("OPENAI_API_KEY")

      System.delete_env("SLACK_BOT_TOKEN")
      System.delete_env("SLACK_BOT_USER_ID")
      File.rm_rf(raw_path)
    end)

    {:ok, tenant} =
      Memory.create_tenant(%{
        name: "Writing Tenant #{System.unique_integer([:positive])}",
        slug: "writing-#{System.unique_integer([:positive])}",
        status: "active"
      })

    {:ok, agent} =
      Memory.create_agent(tenant.id, %{
        name: "Writer Agent",
        identity: "Answer from governed memory.",
        model: "gpt-4.1-mini",
        runtime: "openclaw",
        status: "active"
      })

    %{tenant: tenant, agent: agent}
  end

  test "write action composes skill + product-collection memory with citations", %{
    tenant: tenant,
    agent: agent
  } do
    # Skill = HOW.
    {:ok, skill} =
      Skills.install(tenant.id, %{
        "SKILL.md" => File.read!("priv/fixtures/skills/cold-email/SKILL.md")
      })

    :ok = Skills.enable_for_agent(tenant.id, skill.id, agent.id)

    # Product collection = WHAT.
    {:ok, collection} =
      Memory.create_collection(tenant.id, %{
        "name" => "Product positioning",
        "kind" => "product",
        "description" => "Positioning and audience docs for the governed memory appliance."
      })

    {:ok, _} =
      Service.ingest(
        tenant.id,
        %{
          source_type: "document",
          source_id: "positioning-1",
          name: "positioning.md",
          permalink_or_url: "https://example.com/positioning",
          collection_id: collection.id
        },
        ["[Product positioning · positioning.md] We sell a governed memory appliance to SMEs."],
        %{"permalink" => "https://example.com/positioning"},
        "tenant",
        "default"
      )

    {:ok, action} =
      Actions.request_action(tenant.id, %{
        kind: "write",
        agent_id: agent.id,
        input_summary: "cold-email for ops leads",
        input: %{"argument" => "cold-email for ops leads at manufacturing SMEs"},
        request_id: "req-write-1",
        slack_channel_id: "CWRITE",
        slack_thread_ts: "1710000000.000700"
      })

    assert action.status == "awaiting_approval"
    {:ok, _} = Actions.approve_action(tenant.id, action.id, "marcel@example.com")
    assert %{success: 1} = Oban.drain_queue(queue: :actions)

    # The model got the skill body and the cited memory.
    assert_received {:openai_request, request}
    assert request.instructions =~ "cold-email"
    assert request.instructions =~ "Subject lines under 6 words"
    assert request.input =~ "governed memory appliance"

    completed = Actions.get_action!(tenant.id, action.id)
    assert completed.status == "completed"

    document = File.read!(completed.result_path)
    assert document =~ "**Skill:** cold-email v#{skill.version}"
    assert document =~ "## Sources"
    assert document =~ "https://example.com/positioning"

    # Skill usage is on the request trace.
    kinds = tenant.id |> Audit.list_request_events("req-write-1") |> Enum.map(& &1.event_kind)
    assert "skill_used" in kinds
    assert "action_completed" in kinds

    # Deliverable landed in the thread.
    assert_received {:slack_file, "CWRITE", "1710000000.000700", _filename, content}
    assert content =~ "fewer tools, calmer ops"
  end

  test "weekly digest summarizes the week and posts to the busiest channel", %{
    tenant: tenant
  } do
    {:ok, _} =
      Service.ingest(
        tenant.id,
        %{
          source_type: "slack_channel",
          source_id: "CDIGEST",
          name: "#general",
          permalink_or_url: "slack://channel/CDIGEST"
        },
        ["We decided to ship the digest feature."],
        %{"slack_channel" => "CDIGEST"},
        "tenant",
        "default"
      )

    assert :ok = perform_job(DigestScheduler, %{})
    assert %{success: 1} = Oban.drain_queue(queue: :actions)

    assert_received {:slack_message, "CDIGEST", message, nil}
    assert message =~ "Weekly memory digest"

    assert_received {:slack_file, "CDIGEST", nil, _filename, digest}
    assert digest =~ "# Weekly governed memory digest"
    assert digest =~ "Memory chunks indexed: 1"
    assert digest =~ "#general"
  end

  defp perform_job(worker, args) do
    worker.perform(%Oban.Job{args: args})
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)

  describe "provider routing (AAI-32)" do
    defmodule FakeAnthropic do
      def response(request) do
        send(
          Application.fetch_env!(:andnative_ai, :test_notify_pid),
          {:anthropic_request, request}
        )

        {:ok, "Claude-drafted copy."}
      end
    end

    test "a claude-* write override routes to the anthropic client", %{
      tenant: tenant,
      agent: agent
    } do
      previous_key = System.get_env("ANTHROPIC_API_KEY")
      System.put_env("ANTHROPIC_API_KEY", "sk-ant-test")
      Application.put_env(:andnative_ai, :anthropic_client, FakeAnthropic)

      on_exit(fn ->
        restore_env("ANTHROPIC_API_KEY", previous_key)
        Application.delete_env(:andnative_ai, :anthropic_client)
      end)

      {:ok, _agent} =
        Memory.update_agent_model_policy(agent, %{
          "model_policy" => %{"write" => "claude-opus-4-8"}
        })

      {:ok, action} =
        Actions.request_action(tenant.id, %{
          kind: "write",
          agent_id: agent.id,
          input_summary: "landing page",
          input: %{"argument" => "landing page for launch"},
          request_id: "req-anthropic-1",
          slack_channel_id: "CWRITE",
          slack_thread_ts: "1710000000.000800"
        })

      {:ok, _} = Actions.approve_action(tenant.id, action.id, "marcel@example.com")
      assert %{success: 1} = Oban.drain_queue(queue: :actions)

      assert_received {:anthropic_request, request}
      assert request.model == "claude-opus-4-8"
      assert request.api_key == "sk-ant-test"

      completed = Actions.get_action!(tenant.id, action.id)
      assert completed.status == "completed"
      assert completed.provider == "anthropic/claude-opus-4-8"
    end

    test "a claude-* override with a placeholder anthropic key degrades like a missing one", %{
      tenant: tenant,
      agent: agent
    } do
      previous_key = System.get_env("ANTHROPIC_API_KEY")
      System.put_env("ANTHROPIC_API_KEY", "replace-me")
      on_exit(fn -> restore_env("ANTHROPIC_API_KEY", previous_key) end)

      {:ok, _agent} =
        Memory.update_agent_model_policy(agent, %{
          "model_policy" => %{"write" => "claude-opus-4-8"}
        })

      {:ok, action} =
        Actions.request_action(tenant.id, %{
          kind: "write",
          agent_id: agent.id,
          input_summary: "landing page",
          input: %{"argument" => "landing page for launch"},
          request_id: "req-anthropic-3",
          slack_channel_id: "CWRITE",
          slack_thread_ts: "1710000000.001000"
        })

      {:ok, _} = Actions.approve_action(tenant.id, action.id, "marcel@example.com")
      Oban.drain_queue(queue: :actions)

      failed = Actions.get_action!(tenant.id, action.id)
      refute failed.status == "completed"
      assert failed.error =~ "placeholder_anthropic_api_key"
    end

    test "a claude-* override with no anthropic key degrades honestly", %{
      tenant: tenant,
      agent: agent
    } do
      previous_key = System.get_env("ANTHROPIC_API_KEY")
      System.delete_env("ANTHROPIC_API_KEY")
      on_exit(fn -> restore_env("ANTHROPIC_API_KEY", previous_key) end)

      {:ok, _agent} =
        Memory.update_agent_model_policy(agent, %{
          "model_policy" => %{"write" => "claude-opus-4-8"}
        })

      {:ok, action} =
        Actions.request_action(tenant.id, %{
          kind: "write",
          agent_id: agent.id,
          input_summary: "landing page",
          input: %{"argument" => "landing page for launch"},
          request_id: "req-anthropic-2",
          slack_channel_id: "CWRITE",
          slack_thread_ts: "1710000000.000900"
        })

      {:ok, _} = Actions.approve_action(tenant.id, action.id, "marcel@example.com")
      Oban.drain_queue(queue: :actions)

      failed = Actions.get_action!(tenant.id, action.id)
      refute failed.status == "completed"
      assert failed.error =~ "missing_anthropic_api_key"
    end
  end
end
