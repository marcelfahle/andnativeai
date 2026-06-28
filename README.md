# &native.ai One Week PoC

This repository contains the smallest useful proof for an &native.ai governed
memory appliance: a Phoenix/LiveView control panel, Postgres + pgvector memory
store, filesystem-backed raw source storage, Slack Socket Mode ingestion, and
OpenClaw-shaped runtime answering with persisted audit evidence.

## First Run

```sh
cp .env.example .env
docker compose up --build
```

Then open http://localhost:4000.

The control-panel container runs `mix ecto.create` and `mix ecto.migrate` on
startup. The Postgres service uses the `pgvector/pgvector:pg16` image and the
first migration enables the `vector` extension.

## Local Development Without Docker

```sh
mix setup
mix phx.server
```

Set `DATABASE_HOST`, `DATABASE_PORT`, `DATABASE_NAME`, `DATABASE_USER`, and
`DATABASE_PASSWORD` if your local Postgres differs from `.env.example`.

## Runtime Services

`docker-compose.yml` starts these services:

- `control-panel`: Phoenix/LiveView admin UI and API surface on port 4000.
- `postgres`: pgvector-enabled Postgres with host-mounted state in
  `./var/postgres`.
- `redis`: local queue/cache service with state in `./var/redis`.
- `minio`: placeholder object storage on host ports 59000 and 59001.
- `memory-service`: placeholder process for the external memory API worker.
- `slack-listener`: Socket Mode Slack ingestion and mention responder.
- `openclaw-gateway`: placeholder process for OpenClaw runtime integration.

Host-mounted PoC data lives under `./var/`, which is intentionally gitignored.
Uploaded document files are stored under `RAW_SOURCES_PATH`, defaulting to
`./var/sources`.

Compose maps Postgres to host port 55432 by default so it can run alongside a
local Postgres on 5432. Containers still use `postgres:5432` internally.

## Required Secrets

The PoC can boot without real external credentials. Slack and model-backed
flows use these values:

- `SLACK_APP_TOKEN`: required for Socket Mode.
- `SLACK_CLIENT_ID`, `SLACK_CLIENT_SECRET`, `SLACK_REDIRECT_URI`,
  `SLACK_BOT_SCOPES`: set in `.env` or saved in `/admin/slack` for OAuth.
- `SLACK_BOT_TOKEN` and `SLACK_BOT_USER_ID`: manual fallback for local demos
  and scripts.
- `SLACK_SIGNING_SECRET`: reserved for future HTTP Slack endpoints; not used by
  current Socket Mode.
- `OPENAI_API_KEY` or a future provider-specific LLM/embedding key
- `OPENCLAW_GATEWAY_URL` and `OPENCLAW_WORKSPACE_PATH`

Private-channel Slack scopes are intentionally deferred for the one-week proof.
See `docs/slack-app.md` for the Socket Mode app setup.

## Demo

- `docs/demo-checklist.md` has the repeatable end-to-end script.
- `docs/slack-smoke-test.md` has the short local Slack smoke test.
- `docs/slack-oauth-testing.md` explains how to test Slack OAuth onboarding.
- `docs/agent-setup.md` explains the current agent setup and multiple-agent
  rules.
- `scripts/compose-persistence-check.sh` verifies memory survives a Compose restart.
- `/admin/control-plane` shows the governed-memory control plane, operational
  status, and persisted runtime audit timeline.

## Development Handoff

- `docs/architecture-handoff.md` explains the current system shape, flows,
  limitations, and verification commands.
- `docs/decisions.md` records durable product and implementation decisions.
- `docs/hetzner-demo-deploy.md` records the current single-box demo deployment.
