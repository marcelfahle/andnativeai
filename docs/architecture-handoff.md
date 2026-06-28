# Architecture Handoff

This is a one-tenant PoC for an external governed-memory appliance. The demo
tenant is created by `AndnativeAi.Memory.ensure_demo_tenant!/0` with slug
`native-ai`.

## Services

- `control-panel`: Phoenix/LiveView admin UI and API.
- `slack-listener`: Slack Socket Mode listener.
- `postgres`: pgvector-backed memory store.
- `redis` and `minio`: local placeholders for queue/cache and raw artifacts.
- `memory-service` and `openclaw-gateway`: placeholder containers for future
  service split.

## Core Tables

- `tenants`: customer boundary.
- `agents`: name, identity, model, runtime, sync status, runtime config path.
- `memory_sources`: source-level provenance. Current source types are
  `document`, `slack_channel`, and `slack_thread`.
- `memory_items`: distilled/searchable chunks with embedding, provenance,
  visibility, retention class, optional Slack channel id, and soft-delete state.
- `slack_installations`: OAuth-installed Slack workspaces, keyed by Slack
  `team_id`, with the workspace bot token and bot user ID used for event
  routing and response posting.
- `slack_oauth_configs`: demo tenant Slack app OAuth Client ID/Secret, redirect
  URI, and requested bot scopes. Env vars remain the fallback.

Search excludes deleted sources and deleted items.

## Main Flows

### Admin Control Plane

Path:
`AndnativeAiWeb.Admin.ControlPlaneLive` ->
`AndnativeAi.ControlPlane` ->
current agents, sources, Slack installs, memory items, and OpenClaw health.

Behavior:

- Shows the prospect-facing governed-memory appliance dashboard at
  `/admin/control-plane`.
- Uses live data for source counts, memory chunk counts, Slack installs, agent
  sync health, and source lifecycle events.
- Shows explicit demo-fallback runtime trust events for policy checks, memory
  search, answer generation, citation attachment, routing, and human approval
  until persisted runtime audit events exist.

### Document Upload

Path:
`AndnativeAiWeb.Admin.DocumentsLive` ->
`AndnativeAi.Sources.DocumentIngestion` ->
`AndnativeAi.Memory.Service.ingest/6`

Behavior:

- Accepts `.md` and `.txt`.
- Stores raw file under `RAW_SOURCES_PATH`.
- Splits by markdown headings and chunk size.
- Creates one `memory_sources` row and one or more `memory_items`.
- Delete in Sources soft-deletes the source and all active items.

### Slack Ingestion

Path:
`AndnativeAi.Slack.SocketModeListener` ->
`AndnativeAi.Slack.SocketModeConnection` ->
`AndnativeAi.Slack.Installations.resolve_payload/3` ->
`AndnativeAi.Slack.Ingestion` ->
`AndnativeAi.Slack.Distiller` ->
`AndnativeAi.Memory.Service.ingest/6`

Behavior:

- The app-level `SLACK_APP_TOKEN` opens one Socket Mode WebSocket.
- OAuth installs are stored in `slack_installations`. Incoming Socket Mode
  payloads are routed by Slack `team_id` to the matching tenant and bot token.
- OAuth app credentials can be saved on `/admin/slack` or provided through env.
  The saved config is used for `/slack/install` and `/slack/oauth/callback`.
- If no OAuth install matches, the listener falls back to `.env`
  `SLACK_BOT_TOKEN` and `SLACK_BOT_USER_ID` for the demo tenant. Set
  `SLACK_TEAM_ID` to keep that fallback scoped to one workspace.
- `member_joined_channel` for the bot replaces existing channel memory and
  backfills recent public-channel history.
- Normal messages in already-joined channels are distilled and appended.
- Messages mentioning the bot are answered, but are not stored as knowledge.
- Bot-authored messages are ignored as knowledge.
- Slack edits/deletes replace channel memory and backfill current history.
- `member_left_channel` and `member_kicked_channel` soft-delete the channel
  source if Slack sends the event for the bot user.

### Memory Search

Path:
`AndnativeAi.Memory.Service.search/3`

Behavior:

- Embeddings are local deterministic vectors for PoC repeatability.
- pgvector finds candidate rows.
- A lexical rerank orders exact term matches ahead of fuzzy vector matches.
- Results with zero lexical overlap are rejected to avoid unrelated answers.
- Citations prefer item provenance permalink, then source URL.

### Runtime Answering

Path:
Slack `app_mention` ->
`AndnativeAi.Runtime.Responder` ->
`AndnativeAi.Runtime.OpenClaw.dispatch_mention/2`

Behavior:

- The responder searches memory before answering.
- If `OPENAI_API_KEY` is configured, `OpenAIClient` calls the OpenAI Responses
  API with the agent identity, question, memory context, and citations.
- If no API key is configured or the API call fails, a deterministic fallback
  returns the top memory item and citations.
- The fallback supports the demo instruction
  `Start every conversation with "Yo!"`.
- If no relevant memory exists, the answer says it could not find a relevant
  source.

## Demo Commands

Reset demo memory:

```sh
docker compose exec -T control-panel mix run scripts/reset-demo-memory.exs
```

Backfill an already-joined Slack channel:

```sh
docker compose exec -T control-panel mix run scripts/backfill-slack-channel.exs C0123456789
```

Verify Compose persistence:

```sh
scripts/compose-persistence-check.sh
```

## Verification

Use the Docker Postgres port for local tests:

```sh
DATABASE_PORT=55432 mix test
mix compile --warning-as-errors
docker compose config --quiet
```

## Known Limitations

- One demo tenant only.
- Public Slack channels only.
- Slack channel names are stored as channel IDs unless enriched later.
- Slack app/bot posts such as Linear notifications are not reliably ingested.
  The live message path ignores most Slack `subtype` messages, and the distiller
  currently reads `text` only, not rich `blocks` or `attachments`.
- Slack backfill only sees the most recent `SLACK_HISTORY_LIMIT` messages.
- Embeddings are deterministic local hashes, not production semantic embeddings.
- OpenClaw integration is a config/runtime adapter shape, not a full gateway.
- Admin auth is Caddy basic auth in the demo deploy, not production app auth.
- Slack OAuth app Client Secret and installed bot tokens are plaintext in
  Postgres for the PoC.
- No billing, multi-tenant rollout, load testing, or monitoring.

## Likely Next Work

- Parse Slack `blocks` and `attachments`.
- Allow selected app/bot message subtypes, especially Linear issue updates.
- Add channel/user name hydration for Slack provenance.
- Replace local embeddings with provider embeddings.
- Add source-scoped search/debug UI.
- Add a hard-delete/admin reset endpoint for non-demo environments.
