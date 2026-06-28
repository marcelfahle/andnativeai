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

- Linear and other Slack app posts often arrive as bot/app subtype messages with
  useful text in `blocks` or `attachments`. Current ingestion does not parse
  those deeply, so Linear ticket posts may not become memory.

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
