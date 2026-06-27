# Slack App Setup

Create a Slack app for the PoC and enable Socket Mode.

## Tokens

Set these values in `.env`:

- `SLACK_APP_TOKEN`: app-level token with `connections:write`.
- `SLACK_BOT_TOKEN`: bot token used for Web API reads/writes.
- `SLACK_BOT_USER_ID`: the bot user ID, used to gate channel join/leave events.
- `SLACK_HISTORY_LIMIT`: optional backfill limit, defaults to `50`.

## Bot OAuth Scopes

Required public-channel scopes:

- `channels:history`
- `channels:read`
- `app_mentions:read`
- `chat:write`

Private-channel scopes are intentionally deferred for the one-week PoC.

## Event Subscriptions

Subscribe to bot events:

- `member_joined_channel`
- `member_left_channel`
- `message.channels`
- `app_mention`

Invite the bot into a public channel to trigger backfill. Removing the bot from
the channel soft-deletes the Slack channel memory source.
