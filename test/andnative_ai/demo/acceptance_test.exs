defmodule AndnativeAi.Demo.AcceptanceTest do
  use AndnativeAi.DataCase, async: false

  alias AndnativeAi.Memory
  alias AndnativeAi.Memory.Service
  alias AndnativeAi.Runtime.OpenClaw
  alias AndnativeAi.Slack.Ingestion
  alias AndnativeAi.Sources.DocumentIngestion

  defmodule FakeSlackClient do
    def conversations_history(_token, "CDEMO", _opts) do
      "priv/fixtures/demo/slack_thread.json"
      |> File.read!()
      |> Jason.decode!()
      |> then(&{:ok, &1})
    end

    def conversations_history(_token, _channel, _opts), do: {:ok, []}

    def permalink(_token, channel, ts),
      do: {:ok, "https://example.slack.com/archives/#{channel}/#{ts}"}
  end

  setup do
    raw_path =
      Path.join(System.tmp_dir!(), "andnative-demo-#{System.unique_integer([:positive])}")

    previous_path = Application.get_env(:andnative_ai, :raw_sources_path)
    Application.put_env(:andnative_ai, :raw_sources_path, raw_path)

    on_exit(fn ->
      if previous_path do
        Application.put_env(:andnative_ai, :raw_sources_path, previous_path)
      else
        Application.delete_env(:andnative_ai, :raw_sources_path)
      end

      File.rm_rf(raw_path)
    end)

    :ok
  end

  test "end-to-end demo retrieves Slack and uploaded document memory with citations and honors delete" do
    {:ok, tenant} =
      Memory.create_tenant(%{name: "Demo Acceptance", slug: "demo-acceptance", status: "active"})

    {:ok, agent} =
      Memory.create_agent(tenant.id, %{
        name: "Demo Agent",
        identity: "Answer from governed memory.",
        model: "gpt-4.1-mini",
        runtime: "openclaw",
        status: "active"
      })

    assert {:ok, %{source: doc_source}} =
             DocumentIngestion.ingest_upload(tenant.id, %{
               path: "priv/fixtures/demo/handbook.md",
               filename: "handbook.md"
             })

    assert {:ok, %{items: [_slack_item]}} =
             Ingestion.handle_event(
               tenant.id,
               %{"type" => "member_joined_channel", "user" => "UBOT", "channel" => "CDEMO"},
               client: FakeSlackClient,
               bot_token: "xoxb-test",
               bot_user_id: "UBOT",
               history_limit: 10
             )

    [doc_result | _] = Service.search(tenant.id, "reimbursement approval", %{limit: 2})
    assert doc_result.source.name == "handbook.md"
    assert doc_result.citation_url =~ "handbook.md"

    assert {:ok, response} =
             OpenClaw.dispatch_mention(agent, %{
               "type" => "app_mention",
               "text" => "<@UBOT> Who owns the pilot launch decision?"
             })

    assert response.answer =~ "Ada"
    assert response.answer =~ "example.slack.com"
    assert Enum.any?(response.citations, &String.contains?(&1, "example.slack.com"))

    # Governed forgetting, step 1: while the handbook exists, the agent
    # answers the reimbursement question from it, with a citation.
    reimbursement_question = "<@UBOT> When do reimbursements need manager approval?"

    assert {:ok, known_response} =
             OpenClaw.dispatch_mention(agent, %{
               "type" => "app_mention",
               "text" => reimbursement_question
             })

    # Assert the handbook's distinctive fact, not just words from the
    # question, so this proves grounded retrieval rather than echoing.
    assert known_response.answer =~ "above 500"
    assert known_response.answer =~ "manager approval"
    refute known_response.answer =~ "could not find"
    assert Enum.any?(known_response.citations, &String.contains?(&1, "handbook.md"))

    assert {:ok, %{deleted_items_count: deleted_count}} =
             DocumentIngestion.delete_source(tenant.id, doc_source.id)

    assert deleted_count > 0

    refute Enum.any?(
             Service.search(tenant.id, "reimbursement approval", %{limit: 5}),
             &(&1.source.name == "handbook.md")
           )

    # Governed forgetting, step 2: the same question after source deletion
    # must no longer be answerable from the deleted handbook.
    assert {:ok, unknown_response} =
             OpenClaw.dispatch_mention(agent, %{
               "type" => "app_mention",
               "text" => reimbursement_question
             })

    assert unknown_response.answer =~ "could not find"
    assert unknown_response.citations == []
  end
end
