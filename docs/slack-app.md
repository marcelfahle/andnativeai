# Slack App Setup

This PoC uses Slack Socket Mode. That means the local `slack-listener` service
opens a WebSocket to Slack, so you do not need a public HTTPS request URL or
ngrok for the demo.

## Fastest Path: Create From Manifest

1. Open `https://api.slack.com/apps`.
2. Click **Create New App**.
3. Choose **From an app manifest**.
4. Pick the workspace you want to test in.
5. Paste this manifest and create the app:

```yaml
display_information:
  name: andnative-ai-poc
features:
  bot_user:
    display_name: andnative-ai
    always_online: false
oauth_config:
  redirect_urls:
    - http://localhost:4000/slack/oauth/callback
  scopes:
    bot:
      - app_mentions:read
      - channels:history
      - channels:read
      - chat:write
settings:
  event_subscriptions:
    bot_events:
      - app_mention
      - member_joined_channel
      - member_left_channel
      - message.channels
  org_deploy_enabled: false
  socket_mode_enabled: true
  token_rotation_enabled: false
```

6. Open **OAuth & Permissions**.
7. Add the deployed callback URL if you are testing the Hetzner demo:
   `https://andnativeai.marcelfahle.net/slack/oauth/callback`.
8. Open **Basic Information**.
9. Copy the **Client ID** and **Client Secret** for OAuth installs.
10. Under **App-Level Tokens**, create a token with the `connections:write`
    scope. Copy it. It starts with `xapp-`.

If Slack rejects the manifest or the UI has changed, use the manual setup below.

## Manual Setup

### 1. Create The App

1. Open `https://api.slack.com/apps`.
2. Click **Create New App**.
3. Choose **From scratch**.
4. Name it `andnative-ai-poc`.
5. Select the test workspace.

### 2. Add Bot Scopes

Go to **OAuth & Permissions** and add these **Bot Token Scopes**:

- `app_mentions:read`: receive `@bot` mentions.
- `channels:history`: read recent public-channel messages for backfill.
- `channels:read`: read public-channel metadata.
- `chat:write`: post answers back to Slack.

Private-channel scopes are intentionally deferred for the one-week PoC.

Add this **Redirect URL** under **OAuth & Permissions**:

```text
http://localhost:4000/slack/oauth/callback
```

For the Hetzner demo, also add:

```text
https://andnativeai.marcelfahle.net/slack/oauth/callback
```

### 3. Enable Socket Mode

1. Go to **Socket Mode**.
2. Toggle **Enable Socket Mode** on.
3. When Slack asks for an app-level token, create one with:
   - Name: `local-socket-mode`
   - Scope: `connections:write`
4. Copy the generated app-level token. It starts with `xapp-`.

This token is `SLACK_APP_TOKEN`.

### 4. Subscribe To Bot Events

Go to **Event Subscriptions** and enable events.

Because Socket Mode is enabled, Slack should not require a public request URL.
Add these **Subscribe to bot events** entries:

- `app_mention`
- `member_joined_channel`
- `member_left_channel`
- `message.channels`

The PoC uses these as follows:

- `member_joined_channel`: when the bot is invited, create/update the Slack
  channel source and backfill recent history.
- `message.channels`: ingest new durable public-channel messages after the bot
  has joined.
- `app_mention`: answer from memory and post back in the thread.
- `member_left_channel`: soft-delete that Slack channel source.

### 5. Install Or Reinstall

Go back to **OAuth & Permissions** and install the app to the workspace. If you
changed scopes, redirect URLs, or events after installing, click
**Reinstall to Workspace**.

Copy the **Bot User OAuth Token**. It starts with `xoxb-`.

This token is the manual `.env` fallback `SLACK_BOT_TOKEN`. The preferred demo
flow is now `/admin/slack` -> save the OAuth app settings -> **Connect Slack**,
which exchanges the OAuth code and stores the workspace bot token in Postgres.

## Environment Variables

Add these values to `.env`:

```sh
SLACK_SOCKET_MODE=true
SLACK_APP_TOKEN=xapp-replace-me
SLACK_BOT_TOKEN=xoxb-replace-me
SLACK_BOT_USER_ID=U_REPLACE_ME
SLACK_HISTORY_LIMIT=50
SLACK_CLIENT_ID=123.456
SLACK_CLIENT_SECRET=replace-me
SLACK_REDIRECT_URI=http://localhost:4000/slack/oauth/callback
SLACK_BOT_SCOPES=app_mentions:read,channels:history,channels:read,chat:write
```

`SLACK_SIGNING_SECRET` is present in `.env.example` for future HTTP endpoint
support, but the current Socket Mode listener does not use it.

`SLACK_APP_TOKEN` remains required because Socket Mode uses the app-level
`xapp-` token to open the WebSocket. `SLACK_CLIENT_ID`,
`SLACK_CLIENT_SECRET`, `SLACK_REDIRECT_URI`, and `SLACK_BOT_SCOPES` can be set
in `.env` or saved in `/admin/slack` for the demo tenant. `SLACK_BOT_TOKEN`
and `SLACK_BOT_USER_ID` are kept as a local/manual fallback. OAuth installs
store the active workspace bot token and bot user ID in `slack_installations`.

Current PoC caveat: saved OAuth app settings are plaintext in Postgres.
Production needs encrypted secret storage.

To get `SLACK_BOT_USER_ID`, run:

```sh
source .env
curl -s -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
  https://slack.com/api/auth.test
```

Use the returned `user_id`, which looks like `U012ABCDEF`. The app needs this
ID so it only backfills or deletes memory when the bot itself joins or leaves a
channel.

## Run The Listener

Start the required services:

```sh
docker compose up --build postgres redis minio control-panel slack-listener
```

Then open the Slack app in the test workspace and invite the bot to a public
channel:

```text
/invite @andnative-ai
```

The invite triggers a public-channel backfill. New channel messages are only
ingested after the bot has joined the channel.

## OAuth Install Flow

For a shorter test checklist, see `docs/slack-oauth-testing.md`.

1. Ensure `.env` has `SLACK_APP_TOKEN`.
2. Start `control-panel` and `slack-listener`.
3. Open `/admin/slack`.
4. Save the Slack app **Client ID**, **Client Secret**, Redirect URI, and bot
   scopes in **OAuth app settings**.
5. Click **Connect Slack**.
6. Approve the app in Slack.
7. Confirm `/admin/slack` shows the installed workspace.

Socket Mode receives events for the Slack app. The listener extracts the event
`team_id`, loads the matching `slack_installations` row, and passes that
workspace's bot token into ingestion and response posting. If no install
matches, the old `.env` fallback is used only when `SLACK_BOT_TOKEN` and
`SLACK_BOT_USER_ID` are configured. Set `SLACK_TEAM_ID` to prevent fallback
events from other workspaces.

## How Slack Memory Refresh Works

Slack messages are distilled into channel-level memory items. The PoC does not
store every Slack message as a separate row.

- Inviting the bot backfills recent channel history and replaces existing memory
  for that Slack channel.
- New normal channel messages are distilled and appended.
- Messages that mention the bot are answered, but are not stored as knowledge.
- Slack message edits/deletes trigger a fresh backfill for that channel, so
  deleted demo chatter should age out of memory once Slack sends the event.
- Removing the bot from the channel soft-deletes that channel source and hides
  its memory from search.

Slack app posts, including Linear issue notifications, are a current limitation.
They often arrive as bot/app subtype messages with useful content inside
`blocks` or `attachments`. The PoC currently focuses on human channel messages
with plain `text`, so these notifications may not be distilled into memory.
See `docs/architecture-handoff.md` and `docs/decisions.md` before changing this.

For a clean recorded demo, run:

```sh
docker compose exec -T control-panel mix run scripts/reset-demo-memory.exs
```

## Smoke Test

1. In the joined public channel, post a durable decision:

   ```text
   We decided to launch the pilot with OpenClaw on Monday.
   Owner will be Ada and citations should point back to Slack.
   ```

2. Mention the bot:

   ```text
   @andnative-ai who owns the pilot launch decision?
   ```

3. Confirm the bot replies in Slack and includes a Slack permalink citation.
4. Open `http://localhost:4000/admin/slack` and confirm the channel appears.
5. Remove the bot from the channel.
6. Confirm future memory searches no longer return that channel source.

## Troubleshooting

- `Slack Socket Mode listener disabled`: `.env` is missing `SLACK_APP_TOKEN`
  or it still contains `replace-me`.
- **Connect Slack** is disabled: save Client ID and Client Secret in
  `/admin/slack`, or set `SLACK_CLIENT_ID` and `SLACK_CLIENT_SECRET` in `.env`.
- OAuth returns `bad_redirect_uri`: add the exact `SLACK_REDIRECT_URI` value in
  the Slack app's **OAuth & Permissions** redirect URLs.
- `invalid_auth` from Slack: confirm you used the `xapp-` token for
  `SLACK_APP_TOKEN` and the `xoxb-` token for `SLACK_BOT_TOKEN`.
- Bot does not answer mentions: reinstall the app after adding
  `app_mentions:read` and confirm the `slack-listener` service is running.
- Channel does not backfill: confirm the bot was invited to the channel and
  that `channels:history` is installed on the bot token.
- No Slack permalink citation: confirm `chat.getPermalink` can access the
  channel. The code falls back to a `slack://channel/...` citation if Slack does
  not return a permalink.
