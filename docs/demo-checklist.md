# One Week PoC Demo Checklist

## Fresh Start

- Copy `.env.example` to `.env`.
- Set Slack tokens if running the live Slack smoke test.
- Run `docker compose up --build`.
- Open `http://localhost:4000/admin/agents`.

## Reset Demo Memory

Before recording, clear old uploaded documents and Slack source memory:

```sh
docker compose exec -T control-panel mix run scripts/reset-demo-memory.exs
```

This keeps agents and config, but removes memory sources and memory items for
the demo tenant.

If the bot is already in the Slack channel, post the demo decision and backfill
that existing channel manually:

```sh
docker compose exec -T control-panel mix run scripts/backfill-slack-channel.exs C0123456789
```

Use the channel ID from the Slack channel URL. It is the `C...` value in a URL
like `/archives/C0123456789`.

## Setup

- Create an OpenClaw agent in Agents.
- Sync the agent.

## Slack

- Invite the bot to a public Slack channel.
- Post the pilot-launch decision:
  - `We decided to launch the pilot with OpenClaw on Monday.`
  - `Owner will be Ada and citations should point back to Slack.`
- Confirm the Slack channel appears in Slack and Sources.
- Ask `@andnative-ai who owns the pilot launch decision?`
- Verify the response includes Ada and a Slack permalink.

## Document Memory

- Ask `@andnative-ai when do reimbursements need manager approval?`
- Confirm it does not know yet.
- Upload `priv/fixtures/demo/handbook.md` in Sources.
- Confirm the uploaded document appears as `ready`.
- Ask the reimbursement question again.
- Verify the response says reimbursements above 500 need support escalation and
  manager approval, with a handbook source URL.

## Source Delete

- Delete the uploaded handbook source in Sources.
- Search or ask the same handbook question again.
- Confirm the deleted source is absent from results and the bot no longer knows
  the handbook answer.

## Persistence

- Run `scripts/compose-persistence-check.sh`.
- Confirm the probe memory survives the Compose restart.
