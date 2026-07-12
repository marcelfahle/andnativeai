defmodule AndnativeAi.ResearchTest do
  use AndnativeAi.DataCase, async: false

  alias AndnativeAi.Actions
  alias AndnativeAi.Memory
  alias AndnativeAi.Runtime.Audit

  defmodule FakeProvider do
    @behaviour AndnativeAi.Research.Provider

    @impl true
    def submit(query, _opts) do
      send(test_pid(), {:research_submitted, query})
      {:ok, "job-123"}
    end

    @impl true
    def poll("job-123") do
      case Process.get(:poll_count, 0) do
        0 ->
          Process.put(:poll_count, 1)
          {:pending, "job-123"}

        _later ->
          {:done,
           %{
             markdown: "## Findings\n\nMiniMax support shipped in Q2.",
             citations: ["https://example.com/a", "https://example.com/b"],
             provider: "fake/deep-research",
             cost_cents: 42
           }}
      end
    end

    defp test_pid, do: Application.fetch_env!(:andnative_ai, :test_notify_pid)
  end

  defmodule FailingProvider do
    @behaviour AndnativeAi.Research.Provider

    @impl true
    def submit(_query, _opts), do: {:ok, "job-err"}

    @impl true
    def poll("job-err"), do: {:error, {:research_failed, "FAILED", "quota exceeded"}}
  end

  setup do
    Application.put_env(:andnative_ai, :test_notify_pid, self())
    Application.put_env(:andnative_ai, :research_poll_interval_ms, 1)

    raw_path =
      Path.join(System.tmp_dir!(), "andnative-research-#{System.unique_integer([:positive])}")

    previous_path = Application.get_env(:andnative_ai, :raw_sources_path)
    Application.put_env(:andnative_ai, :raw_sources_path, raw_path)

    on_exit(fn ->
      Application.delete_env(:andnative_ai, :test_notify_pid)
      Application.delete_env(:andnative_ai, :research_poll_interval_ms)
      Application.delete_env(:andnative_ai, :research_provider)

      if previous_path,
        do: Application.put_env(:andnative_ai, :raw_sources_path, previous_path),
        else: Application.delete_env(:andnative_ai, :raw_sources_path)

      File.rm_rf(raw_path)
    end)

    {:ok, tenant} =
      Memory.create_tenant(%{
        name: "Research Tenant #{System.unique_integer([:positive])}",
        slug: "research-#{System.unique_integer([:positive])}",
        status: "active"
      })

    %{tenant: tenant}
  end

  test "deep research is approval-gated, polls the provider, and delivers a cited dossier", %{
    tenant: tenant
  } do
    Application.put_env(:andnative_ai, :research_provider, FakeProvider)

    {:ok, action} =
      Actions.request_action(tenant.id, %{
        kind: "deep_research",
        input_summary: "MiniMax support state",
        input: %{"argument" => "MiniMax support state"},
        request_id: "req-research-1"
      })

    # Spends money -> waits for a human.
    assert action.status == "awaiting_approval"

    {:ok, _} = Actions.approve_action(tenant.id, action.id, "marcel@example.com")
    assert %{success: 1} = Oban.drain_queue(queue: :actions)

    assert_received {:research_submitted, "MiniMax support state"}

    completed = Actions.get_action!(tenant.id, action.id)
    assert completed.status == "completed"
    assert completed.provider == "fake/deep-research"
    assert completed.cost_cents == 42

    dossier = File.read!(completed.result_path)
    assert dossier =~ "# Research dossier"
    assert dossier =~ "MiniMax support shipped in Q2."
    assert dossier =~ "## Sources"
    assert dossier =~ "https://example.com/a"

    completed_event =
      tenant.id
      |> Audit.list_request_events("req-research-1")
      |> Enum.find(&(&1.event_kind == "action_completed"))

    assert completed_event.metadata["citation_count"] == 2
    assert completed_event.metadata["cost_cents"] == 42
  end

  test "provider failure fails the action honestly", %{tenant: tenant} do
    Application.put_env(:andnative_ai, :research_provider, FailingProvider)

    {:ok, action} =
      Actions.request_action(tenant.id, %{
        kind: "deep_research",
        input_summary: "doomed research",
        request_id: "req-research-2"
      })

    {:ok, _} = Actions.approve_action(tenant.id, action.id, "marcel@example.com")
    Oban.drain_queue(queue: :actions)

    failed = Actions.get_action!(tenant.id, action.id)
    assert failed.status == "failed"
    assert failed.error =~ "research_failed"
  end

  test "no configured provider fails with a clear reason", %{tenant: tenant} do
    Application.delete_env(:andnative_ai, :research_provider)
    System.delete_env("PERPLEXITY_API_KEY")
    System.delete_env("GEMINI_API_KEY")

    {:ok, action} =
      Actions.request_action(tenant.id, %{
        kind: "deep_research",
        input_summary: "unconfigured research",
        request_id: "req-research-3"
      })

    {:ok, _} = Actions.approve_action(tenant.id, action.id, "marcel@example.com")
    Oban.drain_queue(queue: :actions)

    failed = Actions.get_action!(tenant.id, action.id)
    assert failed.status == "failed"
    assert failed.error =~ "research_provider_not_configured"
  end
end
