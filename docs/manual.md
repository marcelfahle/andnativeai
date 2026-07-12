# &native.ai Appliance Manual

One appliance = one customer: a self-contained AI colleague for Slack,
grounded exclusively in that company's governed memory, with every
retrieval, answer, action, and policy change on an audit trail. This is
the complete map of what exists; deeper docs are linked per section.

## Architecture

Two app containers plus infrastructure, one Docker Compose project per
appliance (several fit on one VM):

| Service | What it runs |
| --- | --- |
| `control-panel` | Phoenix LiveView admin UI + memory service + API |
| `slack-listener` | Slack Socket Mode listener (`SERVICE_ROLE=slack-listener`) |
| `postgres` | pgvector-backed memory store (1536-dim embeddings) |
| `redis`, `minio` | queue/cache and object-storage infrastructure |

Pushes to `main` auto-deploy to the demo appliance
(GitHub Actions → Hetzner); migrations run on boot. Architecture detail:
`docs/architecture-handoff.md`; design history: `docs/decisions.md`.

## Talking to it in Slack

- **Ask**: invite the bot to a channel, then mention it. Answers come
  only from governed memory, formatted for Slack, with a compact
  `Sources:` footer linking to readable source pages (`/sources/:id`).
  Source URLs come from citation plumbing, never from the model.
- **Address an agent by name**: `@andnative-ai jack: how do refunds
  work?` routes to the agent named Jack (its role, skills, model
  policy). No prefix → the first agent answers. Replies post under each
  agent's display name.
- **Actions** (long-running, delivered in-thread as message + `.md`
  file):
  - `research: <topic>` — cited dossier via Perplexity/Gemini
  - `write: <task>` — marketing/business draft from skills × memory
  - `digest:` — weekly digest (also runs on cron)
  - `echo: <text>` — plumbing check
  Sensitive actions pause as `awaiting_approval` on the control plane;
  failures cancel (never silently retry) and land on the audit trail.
- **Skills**: ask an agent "what skills do you have" and it lists them.

Slack app setup and scopes: `docs/slack-app.md`.

## Memory

- **Sources**: Slack channels (invite the bot → backfill + live
  ingestion, with thread distillation) and uploaded documents (`.md`,
  `.txt`, `.zip` folders).
- **Collections**: multi-file uploads are classified
  (propose-and-confirm) into a named corpus — "37signals company
  handbook" — whose context is embedded into every chunk.
- **Retrieval quality**: provider embeddings (OpenAI when keyed,
  deterministic fallback) plus asynchronous contextual situating per
  chunk. Provider switch → `Release.reembed_memory/0`.
- **Forgetting is governed**: deleting a source or collection removes it
  from retrieval immediately and records governance events. Deleted
  collection names can be reused.

## Agents: roles, skills, models

- Customers configure agents by **name, identity, role**
  (general / marketing / ops / research) and **skills** — never a model.
- **Skills** follow the open Agent Skills standard (SKILL.md),
  phase-1 prompt-packs only: anything with scripts or injection syntax
  is rejected at install and audited. Installed per tenant,
  version-pinned, enabled per agent; usage stamps `skill_used` events.
- **Model policy** (superadmin only): per-agent base model plus
  per-capability overrides (chat, write, classify, situate), resolved
  override → base → appliance default. Every change is a
  `model_policy_changed` governance event with before/after and actor.
  Currently OpenAI model IDs only (multi-provider routing: AAI-32).

## Admin UI (all behind app login)

| Page | Purpose |
| --- | --- |
| `/admin/control-plane` | live audit timeline, action approvals, health |
| `/admin/memory` | memory map: what the agent may know, per source |
| `/admin/agents` | agent roles/skills; model policy panel (superadmin) |
| `/admin/sources` | document + collection uploads, channel policies |
| `/admin/skills` | skill pool: install, inspect, enable per agent |
| `/admin/slack` | Slack OAuth connect + install status |
| `/admin/runtime` | runtime/adapter health |
| `/admin/users` | invites, password resets, user admin |
| `/sources/:id` | readable page for any cited document |

## Roles & security

- **admin** (customer) — everything above except model policy.
- **superadmin** (platform staff) — model policy today; fleet surfaces
  later. Grant only via
  `just prod-eval "AndnativeAi.Release.promote_superadmin(\"email\")"`.
- Slack bot tokens and OAuth secrets are AES-256-GCM encrypted at rest
  (`CLOAK_KEY`); secrets are redacted from inspection and audit
  metadata. Uploaded documents render HTML-sanitized. Zip uploads are
  validated against path traversal.

## Operations

`just` is the ops interface (see `justfile`):

| Recipe | Purpose |
| --- | --- |
| `just deploy-watch` | follow the GitHub Actions deploy after a merge |
| `just prod-ps` / `prod-logs` / `prod-restart` | container operations |
| `just prod-eval "<elixir>"` | run release code on the box |
| `just prod-demo-reset` / `prod-demo-backfill C…` | demo data lifecycle |

Provision a new appliance in one command
(`scripts/provision-appliance.sh <slug> <domain> <admin-email>`):
renders secrets, boots an isolated Compose project, seeds the first
admin, prints the go-live checklist — `docs/provisioning.md`.

Key environment (per-appliance `.env`): `PHX_HOST`, `SECRET_KEY_BASE`,
`POSTGRES_PASSWORD`, `CLOAK_KEY`, `OPENAI_API_KEY`,
`PERPLEXITY_API_KEY`/`GEMINI_API_KEY`, `SLACK_*`, `SEED_ADMIN_*`.

## Demo

Scene-by-scene demo script: `docs/demo-script.md` (ingest → ask → cite →
forget → skills → actions → audit).
