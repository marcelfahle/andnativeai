# One Week PoC Demo Checklist

## Fresh Start

- Copy `.env.example` to `.env`.
- Set Slack tokens if running the live Slack smoke test.
- Run `docker compose up --build`.
- Open `http://localhost:4000/admin/agents`.

## Setup

- Create an OpenClaw agent in Agents.
- Sync the agent.
- Upload `priv/fixtures/demo/handbook.md` in Sources.
- Confirm the uploaded document appears as `ready`.

## Slack

- Invite the bot to a public Slack channel.
- Confirm the Slack channel appears in Slack and Sources.
- Ask the bot a question with an `@mention`.
- Verify the response includes a Slack permalink or uploaded document URL.

## Source Delete

- Delete the uploaded handbook source in Sources.
- Search or ask the same handbook question again.
- Confirm the deleted source is absent from results.

## Persistence

- Run `scripts/compose-persistence-check.sh`.
- Confirm the probe memory survives the Compose restart.
