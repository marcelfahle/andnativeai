defmodule AndnativeAi.Slack.DistillerTest do
  use AndnativeAi.DataCase, async: true

  alias AndnativeAi.Memory
  alias AndnativeAi.Memory.Service
  alias AndnativeAi.Slack.Ingestion

  defmodule FakeClient do
    def conversations_history(_token, _channel, _opts), do: {:ok, []}

    def permalink(_token, channel, ts),
      do: {:ok, "https://example.slack.com/archives/#{channel}/#{ts}"}
  end

  @opts [client: FakeClient, bot_token: "xoxb-test", bot_user_id: "UBOT"]

  test "a Slack thread about a decision produces one compact memory item with permalink provenance" do
    tenant = tenant_fixture("distill-decision")

    assert {:ok, %{source: source, items: [item]}} =
             Ingestion.ingest_messages(
               tenant.id,
               "CDECIDE",
               [
                 %{
                   "type" => "message",
                   "channel" => "CDECIDE",
                   "user" => "U1",
                   "ts" => "1710000100.000100",
                   "thread_ts" => "1710000100.000100",
                   "text" => "We decided to launch the pilot with OpenClaw on Monday."
                 },
                 %{
                   "type" => "message",
                   "channel" => "CDECIDE",
                   "user" => "U2",
                   "ts" => "1710000101.000100",
                   "thread_ts" => "1710000100.000100",
                   "text" => "Owner will be Ada and citations should point to Slack."
                 },
                 %{
                   "type" => "message",
                   "channel" => "CDECIDE",
                   "user" => "U3",
                   "ts" => "1710000102.000100",
                   "thread_ts" => "1710000100.000100",
                   "text" => "thanks"
                 }
               ],
               @opts
             )

    assert item.text =~ "We decided to launch"
    assert item.text =~ "Owner will be Ada"
    assert item.provenance["permalink"] =~ "1710000100.000100"
    assert item.provenance["message_count"] == 2
    assert [item] == Memory.list_source_memory_items(tenant.id, source.id)

    [result | _] = Service.search(tenant.id, "decision launch OpenClaw", %{limit: 3})
    assert result.text == item.text
  end

  test "a noisy thread does not create one memory item per message" do
    tenant = tenant_fixture("distill-noise")

    assert {:ok, %{source: source, items: []}} =
             Ingestion.ingest_messages(
               tenant.id,
               "CNOISE",
               [
                 %{
                   "type" => "message",
                   "channel" => "CNOISE",
                   "user" => "U1",
                   "ts" => "1",
                   "text" => "ok"
                 },
                 %{
                   "type" => "message",
                   "channel" => "CNOISE",
                   "user" => "U2",
                   "ts" => "2",
                   "text" => "+1"
                 },
                 %{
                   "type" => "message",
                   "channel" => "CNOISE",
                   "user" => "U3",
                   "ts" => "3",
                   "text" => "thanks"
                 }
               ],
               @opts
             )

    assert [] = Memory.list_source_memory_items(tenant.id, source.id)
    assert [] = Service.search(tenant.id, "thanks", %{limit: 3})
  end

  defp tenant_fixture(slug) do
    {:ok, tenant} =
      Memory.create_tenant(%{
        name: String.upcase(slug),
        slug: slug,
        status: "active"
      })

    tenant
  end
end
