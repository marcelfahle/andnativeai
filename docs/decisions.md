# Decision Log

Concise decisions for future development. Keep this file current when changing
behavior that affects demo semantics, source lifecycle, or runtime answers.

## DEC-001: External Memory Is Source-Scoped

Memory is organized as `memory_sources` plus `memory_items`. Sources own
provenance and lifecycle; items own searchable text and embeddings.

Why:

- Source delete can reliably remove a document or Slack channel from answers.
- Citations can point back to the original source.
- Future connectors can share the same ingest/search/delete contract.

## DEC-002: Deletes Are Soft Deletes

Source deletion sets `deleted_at` on the source and active items. Search filters
deleted rows.

Why:

- Good enough for demo reversibility and auditability.
- Avoids accidental data loss during PoC testing.

Implication:

- Admin reset scripts may hard-delete demo rows, but product delete paths should
  stay source-scoped and searchable rows must filter deleted state.

## DEC-003: Slack Memory Is Distilled, Not A Message Mirror

Slack messages are grouped by thread or time window and distilled into durable
memory. The system should not embed every line of chatter.

Why:

- Keeps memory focused on decisions, facts, preferences, commitments, and open
  loops.
- Avoids answering from repeated bot questions and demo noise.

Current caveat:

- Linear and other Slack app posts arrive as bot/app subtype messages with
  useful text in `blocks` or `attachments`. These are parsed and can become
  memory when the channel opts in; see DEC-014.

## DEC-004: Bot Questions Are Not Knowledge

Messages that mention the bot are answered but ignored by Slack memory
ingestion.

Why:

- A user asking "who owns the decision?" should not become a new fact.
- Prevents repeated demo questions from polluting future retrieval.

## DEC-005: Channel Refresh Replaces Existing Slack Memory

Bot join, manual backfill, and Slack edit/delete refreshes replace existing
channel memory before ingesting current history.

Why:

- Demo behavior needs to be deterministic after cleanup.
- Slack message deletes should age out of memory once Slack sends the event.

## DEC-006: Retrieval Must Reject Unrelated Nearest Neighbors

Search uses pgvector candidates, then lexical reranking, then rejects results
with zero lexical overlap.

Why:

- A reimbursement question should not fall back to unrelated pilot-launch Slack
  memory after the handbook is deleted.
- Deterministic local embeddings are intentionally simple and need a relevance
  guard.

## DEC-007: Agent Identity Should Affect Runtime Answers

Agent identity is stored in `agents.identity`, synced into OpenClaw config, and
sent to the model-backed responder when `OPENAI_API_KEY` is configured.

Why:

- The admin UI promises editable agent behavior.
- The demo can show behavior changes after editing identity and syncing.

Fallback:

- Without an API key, deterministic answering remains available and supports
  the demo phrase `Start every conversation with "Yo!"`.

## DEC-008: OpenClaw Is The First Runtime Shape

The PoC implements an OpenClaw adapter with `sync_agent/1`,
`dispatch_mention/2`, and `health/1`.

Why:

- Keeps runtime integration behind a behavior.
- Leaves room for a future Hermes adapter without rewriting memory ingestion.

## DEC-009: Demo Reset Is Explicit

`scripts/reset-demo-memory.exs` clears demo sources and items while preserving
agents and config.

Why:

- Slack `/remove` and message deletion depend on Slack event delivery.
- A recorded demo needs deterministic setup.

## DEC-010: Private Slack Channels Are Deferred

The Slack app currently targets public channels only.

Why:

- Public channel scopes are enough for the one-week proof.
- Private scopes and governance policy need a more deliberate product decision.

## DEC-011: Slack OAuth Stores Workspace Bot Tokens

Socket Mode still uses one app-level `SLACK_APP_TOKEN`, but workspace bot tokens
come from OAuth installs stored in `slack_installations`.

Why:

- A customer should connect Slack from the admin UI instead of pasting `xoxb`
  tokens into server env.
- Socket Mode payloads include Slack workspace identity, so routing by
  `team_id` keeps ingestion tenant-aware without changing the ingest contract.
- The existing `.env` token path remains useful as a demo fallback while OAuth
  onboarding matures.

Current caveat:

- Bot tokens and saved Slack OAuth Client Secrets are plaintext in Postgres for
  the PoC. Production needs encrypted secret storage and uninstall/revocation
  handling.

## DEC-012: Control Plane Uses Persisted Runtime Audit Evidence

The control plane uses live tenant data for agents, sources, Slack installs,
memory chunks, source lifecycle events, and runtime answer events. Runtime trust
steps are persisted in `runtime_audit_events` instead of being fabricated on
page refresh.

Why:

- Governed memory needs evidence users can inspect, not a synthetic story feed.
- One Slack mention should correlate mention received, memory searched, answer
  generated, citation attached, and Slack post/failure rows through a request id.
- Source lifecycle evidence should be captured when memory changes, not rebuilt
  indirectly from source timestamps.

Implication:

- A fresh demo tenant shows an empty runtime timeline until real ingestion or
  Slack/runtime activity happens.
- Slack-driven request ids are stable for the Slack event when `event_id` or
  channel/timestamp are available; direct runtime calls use generated UUIDs.
- Source lifecycle audit writes are best-effort. Memory changes should not roll
  back just because audit evidence could not be recorded.
- Audit metadata is minimized. It stores ids, counts, statuses, citations, and
  sanitized bounded errors, not bot tokens, raw Slack payloads, raw questions,
  or full answer bodies.
- This is PoC product evidence, not a compliance-grade immutable audit log.

## DEC-013: Main Auto-Deploys To The Hetzner Demo

The GitHub default branch is `main`. Pushes to `main` run the `Deploy Main`
GitHub Actions workflow, which rsyncs application files to `/opt/andnativeai`
and recreates the app containers with Docker Compose.

Why:

- The demo server should reflect merged work without a manual SSH deploy.
- Deploy history should be visible in GitHub Actions.
- The server still owns runtime state, secrets, generated assets, and
  persistent data.

Implication:

- Deploy sync excludes `.env`, `var/`, `_build`, `deps`, and generated
  `priv/static/assets`.
- Manual rsync deploy remains a fallback, not the normal path.

## DEC-014: App/Bot Post Ingestion Is Per-Channel Opt-In

Slack app and bot posts (Linear issue updates and similar) can become memory,
but only when a channel's source policy enables `ingest_bot_messages`. The
default is off. Enabled app posts are normalized from `blocks` and
`attachments` into plain text, tagged as curated app content so distillation
keeps them, and Linear URLs are preserved as `app_link` provenance next to the
Slack permalink. Our own bot's posts are always excluded, and policy toggles
write a `source_policy_changed` audit event.

Why:

- Linear notifications carry durable facts, but arrive as `bot_message`
  subtypes with empty `text`, which the human path ignores.
- A conservative default avoids ingesting noisy CI/monitoring bots without an
  explicit admin decision.
- The policy change itself is governance evidence and belongs on the audit
  timeline.

## DEC-015: Collections Are The Corpus-Context Primitive

Documents can belong to a `collection` (name, kind, required description).
The collection context is prepended to every chunk at ingest
(`[{collection} · {file}] chunk`), search can scope to a collection, the
memory map groups by collection, and deleting a collection soft-deletes every
member source at once. Collection creation is propose-and-confirm: a
classifier (LLM when configured, filename heuristics otherwise) suggests
name/kind/description from the uploaded batch, and a human confirms — the
confirmation and deletion are governance audit events (`collection_created`,
`collection_deleted`).

Why:

- Retrieval and answers need to know what a corpus IS ("the employee
  handbook"), not just its file names; container + description is the
  primitive every mature knowledge product converges on.
- Context-in-chunk-text follows the existing Slack distiller precedent and
  needs no schema change to items.
- Machine suggests, human decides — corpus classification is a governance
  decision and belongs on the timeline.
