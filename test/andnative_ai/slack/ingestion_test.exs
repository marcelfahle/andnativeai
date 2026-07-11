defmodule AndnativeAi.Slack.IngestionTest do
  use AndnativeAi.DataCase, async: true

  alias AndnativeAi.Memory
  alias AndnativeAi.Memory.Service
  alias AndnativeAi.Runtime.Audit
  alias AndnativeAi.Slack.Ingestion

  defmodule FakeClient do
    def conversations_history(_token, "CJOIN", _opts) do
      {:ok,
       [
         %{
           "type" => "message",
           "channel" => "CJOIN",
           "user" => "U1",
           "ts" => "1710000000.000100",
           "text" => "Backfilled launch decision: cite Slack sources."
         }
       ]}
    end

    def conversations_history(_token, _channel, _opts), do: {:ok, []}

    def permalink(_token, channel, ts),
      do: {:ok, "https://example.slack.com/archives/#{channel}/#{ts}"}
  end

  @opts [client: FakeClient, bot_token: "xoxb-test", bot_user_id: "UBOT", history_limit: 10]

  test "inviting the bot into a public channel triggers backfill" do
    tenant = tenant_fixture("slack-join")

    assert {:ok, %{items: [_item]}} =
             Ingestion.handle_event(
               tenant.id,
               %{"type" => "member_joined_channel", "user" => "UBOT", "channel" => "CJOIN"},
               @opts
             )

    [result | _] = Service.search(tenant.id, "launch citation", %{limit: 3})
    assert result.text =~ "Backfilled launch decision"
    assert result.source.external_id == "CJOIN"
    assert result.citation_url =~ "example.slack.com"

    assert Enum.any?(
             Audit.list_recent_events(tenant.id, limit: 10),
             &(&1.event_kind == "source_ingested" and
                 &1.metadata["source_type"] == "slack_channel")
           )
  end

  test "new channel messages after invite are captured" do
    tenant = tenant_fixture("slack-live")

    {:ok, _} =
      Ingestion.handle_event(
        tenant.id,
        %{"type" => "member_joined_channel", "user" => "UBOT", "channel" => "CJOIN"},
        @opts
      )

    assert {:ok, %{items: [_item]}} =
             Ingestion.handle_event(
               tenant.id,
               %{
                 "type" => "message",
                 "channel" => "CJOIN",
                 "user" => "U2",
                 "ts" => "1710000001.000100",
                 "text" => "Live channel message about onboarding approvals."
               },
               @opts
             )

    [result | _] = Service.search(tenant.id, "onboarding approval", %{limit: 3})
    assert result.text =~ "Live channel message"
  end

  test "bot mentions are answered elsewhere but not captured as durable Slack memory" do
    tenant = tenant_fixture("slack-mention-ignore")

    {:ok, _} =
      Ingestion.handle_event(
        tenant.id,
        %{"type" => "member_joined_channel", "user" => "UBOT", "channel" => "CJOIN"},
        @opts
      )

    assert {:ignored, :bot_mention_memory} =
             Ingestion.handle_event(
               tenant.id,
               %{
                 "type" => "message",
                 "channel" => "CJOIN",
                 "user" => "U2",
                 "ts" => "1710000003.000100",
                 "text" => "<@UBOT> when do reimbursements need manager approval?"
               },
               @opts
             )

    refute Enum.any?(
             Service.search(tenant.id, "reimbursements manager approval", %{limit: 5}),
             &String.contains?(&1.text, "reimbursements need manager approval")
           )
  end

  test "Slack message delete refreshes channel memory from current history" do
    tenant = tenant_fixture("slack-delete-refresh")

    {:ok, _} =
      Ingestion.handle_event(
        tenant.id,
        %{"type" => "member_joined_channel", "user" => "UBOT", "channel" => "CJOIN"},
        @opts
      )

    {:ok, _} =
      Ingestion.handle_event(
        tenant.id,
        %{
          "type" => "message",
          "channel" => "CJOIN",
          "user" => "U2",
          "ts" => "1710000004.000100",
          "text" => "Temporary reimbursement approval decision."
        },
        @opts
      )

    assert Enum.any?(
             Service.search(tenant.id, "temporary reimbursement approval", %{limit: 5}),
             &String.contains?(&1.text, "Temporary reimbursement")
           )

    assert {:ok, %{items: [_item]}} =
             Ingestion.handle_event(
               tenant.id,
               %{
                 "type" => "message",
                 "subtype" => "message_deleted",
                 "channel" => "CJOIN",
                 "deleted_ts" => "1710000004.000100"
               },
               @opts
             )

    refute Enum.any?(
             Service.search(tenant.id, "temporary reimbursement approval", %{limit: 5}),
             &String.contains?(&1.text, "Temporary reimbursement")
           )
  end

  test "messages from unjoined channels are ignored" do
    tenant = tenant_fixture("slack-ignore")

    assert {:ignored, :unjoined_channel} =
             Ingestion.handle_event(
               tenant.id,
               %{
                 "type" => "message",
                 "channel" => "CNOPE",
                 "user" => "U2",
                 "ts" => "1710000002.000100",
                 "text" => "Should not ingest"
               },
               @opts
             )

    assert [] = Service.search(tenant.id, "should ingest", %{limit: 3})
  end

  test "removing the bot hides channel memory from search" do
    tenant = tenant_fixture("slack-leave")

    {:ok, _} =
      Ingestion.handle_event(
        tenant.id,
        %{"type" => "member_joined_channel", "user" => "UBOT", "channel" => "CJOIN"},
        @opts
      )

    assert [_result] = Service.search(tenant.id, "launch citation", %{limit: 3})

    assert {:ok, %{deleted_items_count: 1}} =
             Ingestion.handle_event(
               tenant.id,
               %{"type" => "member_left_channel", "user" => "UBOT", "channel" => "CJOIN"},
               @opts
             )

    assert [] = Service.search(tenant.id, "launch citation", %{limit: 3})

    assert Enum.any?(
             Audit.list_recent_events(tenant.id, limit: 10),
             &(&1.event_kind == "source_deleted" and
                 &1.source_id == source_id_for(tenant.id, "CJOIN"))
           )
  end

  describe "app/bot message ingestion" do
    @linear_event %{
      "type" => "message",
      "subtype" => "bot_message",
      "channel" => "CJOIN",
      "bot_id" => "BLINEAR",
      "bot_profile" => %{"name" => "Linear", "user_id" => "ULINEAR"},
      "ts" => "1710000010.000100",
      "text" => "",
      "attachments" => [
        %{
          "title" => "AAI-42 Add MiniMax provider",
          "title_link" => "https://linear.app/native-ai/issue/AAI-42",
          "text" => "Status changed to Done",
          "fields" => [%{"title" => "Assignee", "value" => "Marcel"}]
        }
      ]
    }

    test "app messages are ignored by default" do
      tenant = tenant_fixture("slack-app-off")

      {:ok, _} =
        Ingestion.handle_event(
          tenant.id,
          %{"type" => "member_joined_channel", "user" => "UBOT", "channel" => "CJOIN"},
          @opts
        )

      assert {:ignored, :bot_ingestion_disabled} =
               Ingestion.handle_event(tenant.id, @linear_event, @opts)

      refute Enum.any?(
               Service.search(tenant.id, "MiniMax provider", %{limit: 5}),
               &String.contains?(&1.text, "MiniMax")
             )
    end

    test "enabled channels ingest Linear notifications as searchable memory" do
      tenant = tenant_fixture("slack-app-on")

      {:ok, _} =
        Ingestion.handle_event(
          tenant.id,
          %{"type" => "member_joined_channel", "user" => "UBOT", "channel" => "CJOIN"},
          @opts
        )

      source = Memory.get_source_by_external_id(tenant.id, "slack_channel", "CJOIN")

      {:ok, _source} =
        Memory.update_source_settings(tenant.id, source.id, %{"ingest_bot_messages" => true})

      assert {:ok, %{items: [_item]}} = Ingestion.handle_event(tenant.id, @linear_event, @opts)

      [result | _] = Service.search(tenant.id, "did we add MiniMax?", %{limit: 3})
      assert result.text =~ "MiniMax"
      assert result.text =~ "Linear update:"
      assert result.citation_url =~ "example.slack.com"
    end

    test "our own bot posts stay excluded even when app ingestion is on" do
      tenant = tenant_fixture("slack-app-self")

      {:ok, _} =
        Ingestion.handle_event(
          tenant.id,
          %{"type" => "member_joined_channel", "user" => "UBOT", "channel" => "CJOIN"},
          @opts
        )

      source = Memory.get_source_by_external_id(tenant.id, "slack_channel", "CJOIN")

      {:ok, _source} =
        Memory.update_source_settings(tenant.id, source.id, %{"ingest_bot_messages" => true})

      self_post = %{
        "type" => "message",
        "subtype" => "bot_message",
        "channel" => "CJOIN",
        "bot_id" => "BSELF",
        "bot_profile" => %{"name" => "andnative-ai", "user_id" => "UBOT"},
        "ts" => "1710000011.000100",
        "text" => "I decided this is the answer to your approval question."
      }

      assert {:ignored, :bot_authored_message} =
               Ingestion.handle_event(tenant.id, self_post, @opts)
    end

    test "policy toggle records a governance audit event" do
      tenant = tenant_fixture("slack-app-audit")

      {:ok, _} =
        Ingestion.handle_event(
          tenant.id,
          %{"type" => "member_joined_channel", "user" => "UBOT", "channel" => "CJOIN"},
          @opts
        )

      source = Memory.get_source_by_external_id(tenant.id, "slack_channel", "CJOIN")

      {:ok, _source} =
        Memory.update_source_settings(
          tenant.id,
          source.id,
          %{"ingest_bot_messages" => true},
          actor: "marcel@example.com"
        )

      assert Enum.any?(
               Audit.list_recent_events(tenant.id, limit: 10),
               &(&1.event_kind == "source_policy_changed" and
                   &1.metadata["changed_settings"]["ingest_bot_messages"] == true and
                   &1.actor == "marcel@example.com")
             )
    end

    test "backfill drops app messages when the channel policy is off" do
      tenant = tenant_fixture("slack-app-backfill")

      {:ok, _} =
        Ingestion.handle_event(
          tenant.id,
          %{"type" => "member_joined_channel", "user" => "UBOT", "channel" => "CAPPMIX"},
          Keyword.put(@opts, :client, __MODULE__.FakeClientWithAppMessages)
        )

      refute Enum.any?(
               Service.search(tenant.id, "MiniMax provider", %{limit: 5}),
               &String.contains?(&1.text, "MiniMax")
             )

      assert Enum.any?(
               Service.search(tenant.id, "decided to launch the pilot", %{limit: 5}),
               &String.contains?(&1.text, "decided to launch")
             )
    end

    test "backfill keeps app messages when the channel policy is on" do
      tenant = tenant_fixture("slack-app-backfill-on")

      {:ok, _source} =
        Memory.create_source(tenant.id, %{
          source_type: "slack_channel",
          source_id: "CAPPMIX",
          name: "Slack CAPPMIX",
          status: "ready",
          settings: %{"ingest_bot_messages" => true}
        })

      {:ok, _} =
        Ingestion.backfill_channel(
          tenant.id,
          %{"channel" => "CAPPMIX"},
          Keyword.put(@opts, :client, __MODULE__.FakeClientWithAppMessages)
        )

      assert Enum.any?(
               Service.search(tenant.id, "MiniMax provider", %{limit: 5}),
               &String.contains?(&1.text, "MiniMax")
             )
    end
  end

  defmodule FakeClientWithAppMessages do
    def conversations_history(_token, "CAPPMIX", _opts) do
      {:ok,
       [
         %{
           "type" => "message",
           "channel" => "CAPPMIX",
           "user" => "U1",
           "ts" => "1710000000.000100",
           "text" => "We decided to launch the pilot next week."
         },
         %{
           "type" => "message",
           "subtype" => "bot_message",
           "channel" => "CAPPMIX",
           "bot_id" => "BLINEAR",
           "bot_profile" => %{"name" => "Linear", "user_id" => "ULINEAR"},
           "ts" => "1710000001.000100",
           "text" => "",
           "attachments" => [
             %{
               "title" => "AAI-42 Add MiniMax provider",
               "title_link" => "https://linear.app/native-ai/issue/AAI-42",
               "text" => "Status changed to Done"
             }
           ]
         }
       ]}
    end

    def conversations_history(_token, _channel, _opts), do: {:ok, []}

    def permalink(_token, channel, ts),
      do: {:ok, "https://example.slack.com/archives/#{channel}/#{ts}"}
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

  defp source_id_for(tenant_id, channel_id) do
    tenant_id
    |> Memory.get_source_by_external_id("slack_channel", channel_id)
    |> Map.fetch!(:id)
  end
end
