# Architecture Handoff

This is a one-tenant PoC for an external governed-memory appliance. The demo
tenant is created by `AndnativeAi.Memory.ensure_demo_tenant!/0` with slug
`native-ai`.

## Services

- `control-panel`: Phoenix/LiveView admin UI and API.
- `slack-listener`: Slack Socket Mode listener.
- `postgres`: pgvector-backed memory store.
- `redis`: local queue/cache placeholder.
- `minio`: local object-storage placeholder. Current document upload stores
  raw files on disk under `RAW_SOURCES_PATH`.

The memory service and OpenClaw adapter run inside the `control-panel` and
`slack-listener` releases; the `RuntimeAdapter` behaviour and
`OPENCLAW_GATEWAY_URL` keep a future service split additive (DEC-019).

## Core Tables

- `tenants`: customer boundary.
- `agents`: name, identity, model, runtime, sync status, runtime config path.
- `memory_sources`: source-level provenance. Current source types are
  `document`, `slack_channel`, and `slack_thread`.
- `memory_items`: distilled/searchable chunks with embedding, provenance,
  visibility, retention class, optional Slack channel id, and soft-delete state.
- `runtime_audit_events`: persisted control-plane evidence for source
  lifecycle and runtime answering. Rows are tenant-scoped and can link to an
  agent, source, memory item, request id, citation URL, and minimized metadata.
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
current agents, source counts, Slack install count, memory chunk count, OpenClaw
health, and recent audit rows.

Behavior:

- Shows the prospect-facing governed-memory appliance dashboard at
  `/admin/control-plane`.
- Uses live data for source counts, memory chunk counts, Slack installs, agent
  sync health, and persisted audit events. An Outcomes section adds
  business-facing tiles: questions answered, answers with citations, a labeled
  time-saved estimate, a labeled model-spend placeholder, and a state-aware
  "next step" recommendation card.
- Shows an honest empty state when no runtime audit events exist. The page no
  longer fabricates runtime trust events on refresh.
- The Governed activity timeline is backed by `Audit.list_events/2` with
  category filter chips (memory, runtime, governance, errors, with counts),
  free-text search over request id/summary/actor/kind, and cursor-based
  "load older" pagination.
- New audit rows stream in live over Phoenix.PubSub
  (`Audit.subscribe/1` -> `{:audit_event_recorded, event}`); rows animate in
  and counters update without a refresh.
- Clicking a row opens an inspector panel with status, actor, component,
  request id, citation link or label, sanitized metadata ("Evidence"), and the
  correlated request trace (`Audit.list_request_events/2`) with relative
  timing offsets. Trace steps are clickable.
- Event-kind validation, display metadata, and filter categories share
  `AndnativeAi.Runtime.AuditEventKinds` so the schema and UI do not drift.

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

### Collections

Path:
`AndnativeAiWeb.Admin.DocumentsLive` (New collection) ->
`AndnativeAi.Sources.DocumentIngestion.stage_upload/2` ->
`AndnativeAi.Sources.CollectionClassifier.propose/2` ->
`AndnativeAi.Memory.create_collection/3` ->
`DocumentIngestion.ingest_staged/3`

Behavior:

- Multi-file upload (.md/.txt, or a folder as .zip) auto-stages each file as
  it finishes transferring; nothing enters memory while staged.
- A classifier proposes collection name/kind/description (OpenAI when
  `OPENAI_API_KEY` is set, filename heuristics otherwise); the admin confirms
  or edits — the confirmation is a `collection_created` governance audit
  event.
- Each ingested chunk gets the collection context prefix
  `[{collection.name} · {source.name}]` so retrieval knows what the chunk is;
  search accepts `scope.collection_id`; the memory map groups sources by
  collection.
- Deleting a collection soft-deletes all member sources (audited as
  `collection_deleted` plus per-source events).

### Slack Ingestion

Path:
`AndnativeAi.Slack.SocketModeListener` ->
`AndnativeAi.Slack.SocketModeConnection` ->
`AndnativeAi.Slack.Installations.resolve_payload/3` ->
`AndnativeAi.Slack.Ingestion` ->
`AndnativeAi.Slack.Distiller` ->
`AndnativeAi.Memory.Service.ingest/6` ->
`AndnativeAi.Runtime.Audit`

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
- App/bot posts (Linear notifications and similar) are ingested only when the
  channel's source policy enables `ingest_bot_messages` (toggle on the Sources
  page; default off). `AndnativeAi.Slack.MessageText` flattens `blocks` and
  `attachments` into searchable text, keeps the Linear issue URL as `app_link`
  provenance, and the policy toggle writes a `source_policy_changed` audit
  event. The app's own bot posts are always excluded.
- Slack edits/deletes replace channel memory and backfill current history.
- `member_left_channel` and `member_kicked_channel` soft-delete the channel
  source if Slack sends the event for the bot user.
- Source ingest, memory indexing, and source delete paths write audit evidence
  for the control plane. These writes are best-effort so memory changes do not
  roll back if audit persistence is temporarily unavailable.

### Agent Actions

Path:
Slack mention with an intent prefix ->
`AndnativeAi.Runtime.Responder` (intent match) ->
`AndnativeAi.Actions.request_action/2` ->
Oban `AndnativeAi.Actions.Worker` ->
kind handler (`AndnativeAi.Actions.Handler` behaviour) ->
Slack thread delivery (`Client.post_message/4` + `Client.upload_file/5`)

Behavior:

- Intent prefixes come from `AndnativeAi.Actions.ActionKinds` (v1 registry:
  `echo:` demo kind, `research:` deep research, `write:` drafts,
  `digest:` on-demand weekly digest). Unmatched mentions fall through to
  the normal governed-memory answer.
- `write:` composes an enabled skill (HOW) with governed memory (WHAT —
  preferring a `product` collection when one exists), drafts via the model
  the agent's policy resolves (Anthropic for `claude-*` overrides, OpenAI
  otherwise), cites the memory used, and records
  `skill_used` on the trace. Approval-gated: the output is
  outward-facing.
- A weekly digest (Oban cron, Monday 08:00 UTC) posts what entered
  memory, what was answered, and the week's governance decisions to each
  tenant's most recently active Slack channel — pure database reads, no
  external spend.
- `research:` submits to the configured `AndnativeAi.Research.Provider`
  (Perplexity `sonar-deep-research` by default via `PERPLEXITY_API_KEY`;
  Gemini Deep Research via `GEMINI_API_KEY`), polls until the cited report
  is ready, and delivers a markdown dossier with a Sources section. It is
  approval-gated because it spends provider budget; actual cost lands in
  `cost_cents` and on the `action_completed` event when the provider
  reports it.
- The mention gets an immediate threaded ack; the work runs as an Oban job
  (queue `actions`), so it survives restarts and is retried on crashes.
- Kinds with `requires_approval` pause in `awaiting_approval`; the control
  plane lists them with Approve/Deny (audited as
  `action_approved`/`action_denied`), and only approval enqueues the job.
- Deliverables persist under `RAW_SOURCES_PATH/actions/` and are posted to
  the thread as a summary message plus a markdown file (external upload
  flow; `files.upload` is retired).
- Handler failures cancel the job (no silent budget re-spend), notify the
  thread, and record `action_failed` with a sanitized reason.
- All action audit events share the Slack request id, so the control-plane
  inspector shows the full mention -> approval -> execution -> delivery
  trace. Timeline chips gain an Actions category.

### Skills

Path:
`AndnativeAiWeb.Admin.SkillsLive` ->
`AndnativeAi.Skills.install_from_upload/4` ->
`AndnativeAi.Skills.Parser` ->
`AndnativeAi.Runtime.OpenClaw` (prompt integration)

Behavior:

- Prompt-pack skills only (Agent Skills standard): SKILL.md frontmatter is
  validated (name/description constraints); bundles with `scripts/`,
  `allowed-tools`, or dynamic `` !`command` `` injection are rejected and the
  rejection is audited (`skill_rejected`).
- Skills are version-pinned by content hash; install/enable/disable/remove
  are governance audit events.
- Progressive disclosure: enabled skills add name+description to the agent
  instructions; when a request names a skill, its body is included and
  `skill_used` (with version) lands on the request trace.
- Admin page at `/admin/skills`: install from .zip or SKILL.md, per-agent
  toggles, remove.

### Memory Search

Path:
`AndnativeAi.Memory.Service.search/3`

Behavior:

- Embeddings dispatch to a provider: OpenAI text-embedding-3-small when
  `OPENAI_API_KEY` is set, deterministic local vectors otherwise (the
  control plane's Memory card shows which). Document chunks get an
  LLM-written situating context asynchronously after ingest and are
  re-embedded as context + text. Switching providers requires
  `Release.reembed_memory/0`.
- pgvector finds candidate rows.
- A lexical rerank orders exact term matches ahead of fuzzy vector matches.
- Results with zero lexical overlap are rejected to avoid unrelated answers.
- Citations prefer item provenance permalink, then source URL.

### Runtime Answering

Path:
Slack `app_mention` ->
`AndnativeAi.Runtime.Responder` ->
`AndnativeAi.Runtime.OpenClaw.dispatch_mention/2` ->
`AndnativeAi.Runtime.Audit`

Behavior:

- The responder searches memory before answering.
- If `OPENAI_API_KEY` is configured, `OpenAIClient` calls the OpenAI Responses
  API with the agent identity, question, memory context, and citations.
- If no API key is configured or the API call fails, a deterministic fallback
  returns the top memory item and citations. Configured model-call failures also
  create a `runtime_error` audit row.
- The fallback supports the demo instruction
  `Start every conversation with "Yo!"`.
- If no relevant memory exists, the answer says it could not find a relevant
  source.
- The responder uses Slack `event_id` when present, then channel/timestamp, as a
  stable request id for answered Slack mentions. Direct non-Slack calls generate
  a UUID. Audit rows correlate mention received, memory searched, answer
  generated, citation attached, Slack response posted, skipped/failed delivery,
  and runtime/model failure events.
- Audit metadata is minimized. It stores ids, counts, statuses, citations, and
  sanitized bounded error details rather than full Slack payloads, bot tokens,
  raw questions, or answer bodies.

## Demo Commands

Common commands are `just` recipes (`just --list`). Local stack:

```sh
just demo-reset                    # clear demo memory (mix script)
just demo-backfill C0123456789     # re-ingest a joined Slack channel
just demo-persistence              # verify memory survives a restart
```

Live Hetzner appliance — the box runs an OTP release without Mix, so these
call release-safe tasks in `AndnativeAi.Release`
(`reset_demo_memory/0`, `backfill_slack_channel/1`) via
`bin/andnative_ai eval`:

```sh
just prod-demo-reset
just prod-demo-backfill C0123456789
just prod-restart                  # persistence demo on the live box
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
- Slack app/bot post ingestion is per-channel opt-in and parses `blocks` and
  `attachments`, with Linear-aware URL provenance. Deep parsers for other apps
  (Jira, GitHub) are not implemented; unusual block types fall back to plain
  text fragments.
- Slack backfill only sees the most recent `SLACK_HISTORY_LIMIT` messages.
- Embeddings are deterministic local hashes, not production semantic embeddings.
- OpenClaw integration is a config/runtime adapter shape, not a full gateway.
- Runtime audit is product evidence for the PoC, not a compliance-grade
  immutable audit log.
- Runtime audit rows are append-only in normal app behavior, but duplicate Slack
  retries are not de-duplicated yet.
- Admin auth is still Caddy basic auth in the demo deploy. Phoenix-native app
  auth is tracked separately in Linear as AAI-18.
- Slack OAuth app Client Secret and installed bot tokens are plaintext in
  Postgres for the PoC.
- Deploys from `main` run through GitHub Actions to the Hetzner demo host.
- No billing, multi-tenant rollout, load testing, or monitoring.

## Likely Next Work

- Parse Slack `blocks` and `attachments`.
- Allow selected app/bot message subtypes, especially Linear issue updates.
- Add channel/user name hydration for Slack provenance.
- Replace local embeddings with provider embeddings.
- Add source-scoped search/debug UI.
- Add read-only OpenClaw tools for control-plane snapshot and runtime audit rows
  so agents can inspect the same governance state users see.
- Add idempotency/deduplication for retried Slack event traces if Slack retry
  noise becomes visible in demos.
- Add a hard-delete/admin reset endpoint for non-demo environments.
- Add compliance-grade audit retention/export only if customer requirements
  demand it.
