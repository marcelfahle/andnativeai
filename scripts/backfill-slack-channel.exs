alias AndnativeAi.Memory
alias AndnativeAi.Slack.Ingestion

case System.argv() do
  [channel_id] ->
    tenant = Memory.ensure_demo_tenant!()
    bot_token = System.fetch_env!("SLACK_BOT_TOKEN")
    bot_user_id = System.fetch_env!("SLACK_BOT_USER_ID")
    history_limit = System.get_env("SLACK_HISTORY_LIMIT", "50") |> String.to_integer()

    Ingestion.delete_channel(tenant.id, channel_id)

    {:ok, %{items: items, source: source}} =
      Ingestion.backfill_channel(
        tenant.id,
        %{"channel" => channel_id},
        bot_token: bot_token,
        bot_user_id: bot_user_id,
        history_limit: history_limit
      )

    IO.puts("Backfilled #{length(items)} memory items for #{source.name} (#{source.source_id}).")

  _other ->
    IO.puts("Usage: mix run scripts/backfill-slack-channel.exs C0123456789")
    System.halt(1)
end
