# One Week PoC Demo Checklist

This checklist targets the live Hetzner appliance at
`https://andnativeai.marcelfahle.net`. The local Compose variant is at the
end. `docs/demo-script.md` is the camera-ready scene-by-scene script; this
file is the operational setup around it.

## Live Appliance Facts

- URL: `https://andnativeai.marcelfahle.net` (Caddy may ask for the optional
  basic-auth outer belt first, then the app login).
- Server: `ssh andnative-deploy@91.99.49.152`, app path `/opt/andnativeai`.
- The app runs as an OTP release — there is no Mix on the box. Demo tasks are
  release functions invoked with `bin/andnative_ai eval` inside the
  `andnative-control-panel` container.
- Deploys happen automatically on every push to `main`. Do not demo while a
  deploy is running; check the `Deploy Main` action first.

## Fresh Start (live)

- Log in at `https://andnativeai.marcelfahle.net/login`.
- Slack app connection:
  - `SLACK_APP_TOKEN` (Socket Mode) lives in `/opt/andnativeai/.env` on the
    server.
  - Connect the workspace via OAuth in `/admin/slack`. The Slack app's
    redirect URL must be
    `https://andnativeai.marcelfahle.net/slack/oauth/callback`.
  - The installed workspace shows under Slack connection status.

## Reset Demo Memory (live)

All live-appliance commands are `just` recipes (see the repo `justfile`;
`just --list` shows everything, and each `prod-*` recipe prints the full
ssh command it runs).

Before recording, clear old uploaded documents and Slack source memory:

```sh
just prod-demo-reset
```

This keeps agents and config, but removes memory sources and memory items for
the demo tenant. The audit timeline keeps its historical evidence rows; their
source links are detached.

If the bot is already in the Slack channel, post the demo decision in Slack
and backfill that existing channel:

```sh
just prod-demo-backfill C0123456789
```

Use the channel ID from the Slack channel URL. It is the `C...` value in a
URL like `/archives/C0123456789`. Credentials resolve from the latest OAuth
installation automatically (env `SLACK_BOT_TOKEN`/`SLACK_BOT_USER_ID` remain
the fallback).

## Setup

- Open `https://andnativeai.marcelfahle.net/admin/control-plane` and confirm
  it loads. A fresh tenant shows the "No evidence yet" empty state until
  source or Slack activity creates real events.
- Create one primary OpenClaw agent in Agents. See `docs/agent-setup.md`.
- Optional behavior demo: set Identity to
  `Answer from governed memory with concise citations. Start every conversation with "Yo!"`
  and save.
- Sync the agent.

## Slack

- Invite the bot to a public Slack channel.
- Post the pilot-launch decision:
  - `We decided to launch the pilot with OpenClaw on Monday.`
  - `Owner will be Ada and citations should point back to Slack.`
- Confirm the Slack channel appears in Sources and on the Memory map
  (`/admin/memory`).
- Ask `@andnative-ai who owns the pilot launch decision?`
- Verify the response includes Ada and a Slack permalink.
- Watch Control: the governed activity timeline streams the Slack mention,
  memory search, answer, citation, and response events live — no refresh
  needed. Click any of them to open the inspector and walk the request trace.

## Document Memory

- Ask `@andnative-ai when do reimbursements need manager approval?`
- Confirm it does not know yet.
- Upload `priv/fixtures/demo/handbook.md` (from your local checkout) in
  Sources on the live UI.
- Confirm the uploaded document appears as `ready`.
- Ask the reimbursement question again.
- Verify the response says reimbursements above 500 need support escalation
  and manager approval, with a handbook source URL.

## Source Delete (governed forgetting)

- Delete the uploaded handbook source in Sources.
- Ask the exact same handbook question again.
- Confirm the bot answers that it could not find a relevant source, the
  Memory map shows the source struck through ("deleted — excluded from
  retrieval"), and the timeline records `Source deleted`.

## App/Bot Post Policy (optional)

- In Sources, flip "App & bot posts" ON for the demo channel and point out
  the `Policy changed` governance event on the timeline.
- A Linear notification posted into the channel becomes searchable memory;
  `@andnative-ai did we add MiniMax?` answers with the Slack permalink.

## Persistence (live)

```sh
just prod-restart
```

Reload the control plane after ~30s and confirm source, memory, and evidence
counts are unchanged.

Related recipes: `just prod-ps` (container status), `just prod-logs` (tail
logs), `just deploy-watch` (wait for an in-flight deploy), `just prod-open`
(open the live control plane).

## Local Variant

For local development demos, the original flow still applies:

- Copy `.env.example` to `.env`, set `SLACK_APP_TOKEN` (plus the
  `SLACK_BOT_TOKEN`/`SLACK_BOT_USER_ID` fallback for manual setups).
- `just up`, then open `http://localhost:4000/admin/agents`.
- Reset: `just demo-reset`
- Backfill: `just demo-backfill C0123456789`
- Persistence: `just demo-persistence`
