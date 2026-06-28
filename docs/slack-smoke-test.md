# Manual Slack Smoke Test

Use a public test channel.

For the preferred OAuth path, use `docs/slack-oauth-testing.md`. This checklist
is the shorter local smoke test once the app is already installed or fallback
tokens are configured.

1. Confirm `.env` has `SLACK_APP_TOKEN`.
2. Confirm either:
   - OAuth settings are saved in `/admin/slack` and the workspace is connected,
   - or fallback `SLACK_BOT_TOKEN` and `SLACK_BOT_USER_ID` are set.
3. Run `docker compose up --build slack-listener control-panel postgres redis minio`.
4. Invite the bot to the public channel.
5. Post a thread with a durable decision, such as:
   - `We decided to launch the pilot with OpenClaw on Monday.`
   - `Owner will be Ada and citations should point back to Slack.`
6. Mention the bot in the channel and ask about the decision.
7. Confirm the response cites a Slack permalink.
8. Remove the bot from the channel.
9. Confirm the channel source disappears from future memory search results.
