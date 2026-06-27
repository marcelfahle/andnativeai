# Manual Slack Smoke Test

Use a public test channel.

1. Confirm `.env` has `SLACK_APP_TOKEN`, `SLACK_BOT_TOKEN`, and `SLACK_BOT_USER_ID`.
2. Run `docker compose up --build slack-listener control-panel postgres redis minio`.
3. Invite the bot to the public channel.
4. Post a thread with a durable decision, such as:
   - `We decided to launch the pilot with OpenClaw on Monday.`
   - `Owner will be Ada and citations should point back to Slack.`
5. Mention the bot in the channel and ask about the decision.
6. Confirm the response cites a Slack permalink.
7. Remove the bot from the channel.
8. Confirm the channel source disappears from future memory search results.
