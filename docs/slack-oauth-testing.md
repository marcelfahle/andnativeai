# Slack OAuth Testing

Use this checklist to test customer-style Slack onboarding on the Hetzner demo
or locally.

## Prerequisites

- Slack app has Socket Mode enabled.
- Slack app has an app-level token with `connections:write`.
- `SLACK_APP_TOKEN` is set on the app server. This is still required because
  Socket Mode opens the WebSocket with the app-level `xapp-` token.
- Slack app has these bot scopes:
  - `app_mentions:read`
  - `channels:history`
  - `channels:read`
  - `chat:write`
- Slack app has the matching redirect URL:
  - Hetzner: `https://andnativeai.marcelfahle.net/slack/oauth/callback`
  - Local: `http://localhost:4000/slack/oauth/callback`

## Configure OAuth App Settings

1. Open `/admin/slack`.
2. In **OAuth app settings**, paste:
   - Client ID
   - Client Secret
   - Redirect URI
   - Bot scopes
3. Click **Save settings**.

The Client Secret field is write-only in the UI. After saving, it shows
`Saved; leave blank to keep`. Leaving it blank on later saves keeps the current
secret.

PoC caveat: saved OAuth app settings are plaintext in Postgres. Production needs
encrypted secret storage.

## Connect A Workspace

1. Click **Connect Slack**.
2. Approve the app in Slack.
3. Return to `/admin/slack`.
4. Confirm **Installed workspaces** shows the workspace.
5. Invite the bot to a public channel:

```text
/invite @andnative-ai
```

The invite should create a Slack channel source and backfill recent public
channel history.

## Smoke Test

1. In the invited channel, post:

```text
We decided to launch the pilot with OpenClaw on Monday.
Owner will be Ada and citations should point back to Slack.
```

2. Mention the bot:

```text
@andnative-ai who owns the pilot launch decision?
```

3. Expected result:
   - The bot answers in a thread.
   - The answer mentions Ada.
   - The answer includes a Slack permalink source.

## Remove And Reconnect

- Removing the bot from a channel should soft-delete that channel source when
  Slack delivers `member_left_channel` or `member_kicked_channel`.
- Re-inviting the bot backfills the channel again.
- If Slack events were missed or the bot is already in the channel, run manual
  backfill:

```sh
docker compose exec -T control-panel mix run scripts/backfill-slack-channel.exs C0123456789
```

Use the `C...` channel ID from the Slack channel URL.

## What OAuth Changes

- Before OAuth, the demo can use `.env` fallback values:
  `SLACK_BOT_TOKEN` and `SLACK_BOT_USER_ID`.
- After OAuth, the workspace bot token and bot user ID are stored in
  `slack_installations`.
- Socket Mode receives all app events through the app-level connection and
  routes each event by Slack `team_id` to the matching installation.
- If no installation matches, the `.env` fallback is used only when configured.

## Troubleshooting

- **Connect Slack disabled:** save Client ID and Client Secret in
  `/admin/slack`.
- **Slack shows `bad_redirect_uri`:** the redirect URL in Slack must exactly
  match the URL saved in `/admin/slack`.
- **Bot does not answer:** confirm `app_mentions:read`, `chat:write`, and the
  `app_mention` event subscription are installed, then reinstall the app.
- **Channel does not backfill:** confirm `channels:history`, `channels:read`,
  and `message.channels` are installed, then invite the bot again or run manual
  backfill.
- **Linear/app posts do not appear in memory:** current ingestion focuses on
  human messages with plain `text`. Rich `blocks` and `attachments` are a
  follow-up.
