---
title: "feat: Platform train — invisible superadmins, provisioning workflow, multi-provider routing"
date: 2026-07-13
artifact_contract: ce-unified-plan/v1
artifact_readiness: implementation-ready
execution: code
product_contract_source: ce-plan-bootstrap
origin: Linear AAI-34, AAI-33 (phase A), AAI-32
deepened: 2026-07-13
---

# feat: Platform train — invisible superadmins, provisioning workflow, multi-provider routing

## Summary

Three independent tickets shipped as one reviewed train: platform
superadmins become invisible in customer user management while their
activity stays audited (AAI-34 phase 1); appliance provisioning gets a
GitHub Actions dispatch form plus upgrade recipes (AAI-33 phase A); and
model policy gains real multi-provider routing so `claude-*` models
actually run (AAI-32).

## Problem Frame

- Customer appliances currently seed only the customer's first admin;
  platform staff (Marcel/Matt) either don't exist in the box or would
  appear in the customer's `/admin/users` list — both wrong.
- Provisioning works (`scripts/provision-appliance.sh`) but only via SSH;
  there is no attributable, logged, form-based way to run it, and no
  one-command way to upgrade provisioned appliances after `main` moves.
- `agents.model_policy` accepts any model ID but the runtime only calls
  the OpenAI Responses API; pinning `claude-opus-4-8` for `write` fails
  at call time.

## Requirements

- R1 (AAI-34): Provisioned appliances seed platform superadmin accounts
  for `m.fahle@gmail.com` and `matthewosullivan87@gmail.com` with
  per-appliance generated passwords.
- R2 (AAI-34): Customer-facing `/admin/users` never shows
  `role == "superadmin"` accounts; superadmins are uninvitable,
  undeletable, and un-resendable from that UI.
- R3 (AAI-34): The last-user deletion guard counts only non-superadmin
  active users.
- R4 (AAI-34): Superadmin activity stays visible: logging in as a
  superadmin records a governance audit event.
- **R10 (AAI-34, from security review): superadmin accounts are excluded
  from the public self-serve password-reset flow.** Fixed platform emails
  on every appliance would otherwise make one compromised inbox a
  fleet-wide skeleton key via `/users/reset-password`. Rotation happens
  out-of-band via a Release task instead.
- R5 (AAI-33): A `workflow_dispatch` GitHub Actions workflow provisions
  an appliance from a form (slug, domain, admin email) over the existing
  deploy SSH trust path, without leaking generated credentials into CI
  logs.
- R6 (AAI-33): `just` recipes exist to list appliances
  (`appliance-ls`: directory scan of `/opt/appliances/*/` — explicitly
  NOT the deferred `fleet.yml` inventory) and to upgrade one
  (`appliance-upgrade <slug>`).
- R7 (AAI-32): `ModelPolicy` infers a provider from the model ID
  (`claude-*` → anthropic, everything else → openai).
- R8 (AAI-32): An Anthropic Messages API client exists with the OpenAI
  client's contract (api_key arrives in the request map; call sites read
  env); missing/placeholder key degrades to the deterministic fallback,
  never a crash.
- R9 (AAI-32): Chat runtime and `write:` handler route to the client
  matching the resolved provider; action metadata labels the real
  provider.

## Key Technical Decisions

- **KTD1 — One branch, three commits, one PR.** The three workstreams
  land as three logically separate commits with one Copilot review.
  Known trade-off: rollback couples all three (acceptable at this scale).
- **KTD2 — Seed slots, not a new mechanism (AAI-34).** Two
  `SEED_PLATFORM{1,2}_EMAIL/PASSWORD` slots in `seeds.exs`. Semantics
  (resolving the skip-existing vs promote tension): platform slots
  **always assert `role == "superadmin"`** on an existing user (via
  `set_user_role/2`, idempotent) while **never touching an existing
  user's password**; new users register with the slot password. Platform
  slots run BEFORE the customer `SEED_ADMIN` slot, and the provision
  script **rejects** an `admin_email` equal to a platform email. The
  script generates passwords into the appliance `.env` only; under
  `QUIET_CREDENTIALS=true` it never prints them (nothing for CI logs to
  leak; there is no runtime secret to mask).
- **KTD3 — Filter at the context boundary (AAI-34).**
  `Accounts.list_customer_users/0` for the users LiveView;
  `delete_user/1` guard counts active non-superadmin users;
  `get_user_by_email/1`-based reset delivery skips superadmins (R10).
- **KTD4 — Login audit as a governance event (AAI-34).** Successful
  superadmin login records `platform_access` (governance) against the
  demo tenant via `Memory.ensure_demo_tenant!/0` (guards the
  seeds-not-yet-run window) + `Audit.record_best_effort`.
- **KTD5 — Reuse the deploy trust path (AAI-33).** Same SSH key/user/host
  env as `deploy-main.yml`; workflow carries `permissions: contents: read`
  and passes dispatch inputs to the remote script **via env vars, not
  inline interpolation**. Stated precondition: `andnative-deploy` must
  own `/opt/appliances` (one-time `chown`, documented + fail-fast
  writability check in the workflow).
- **KTD6 — Provider inference by model-ID prefix (AAI-32).**
  `claude-*` → `:anthropic`, default `:openai`. Anthropic client: `Req`
  POST to `https://api.anthropic.com/v1/messages`, headers `x-api-key` +
  `anthropic-version: 2023-06-01`; maps `instructions` → `system`,
  `input` → user message, `max_output_tokens` → `max_tokens`; returns
  first text content block. Call sites read `ANTHROPIC_API_KEY` and pass
  it in the request map (exactly the OpenAI contract), including the
  placeholder-value guard (`replace-me`).
- **KTD7 — classify/situate stay OpenAI-only.** Policy panel hint says
  so explicitly (chat + write route to Anthropic; classify/situate
  remain OpenAI-only) so staff don't enter inert values.
- **KTD8 — Missing Anthropic key mirrors OpenAI exactly (from
  feasibility review).** A missing key returns
  `{:error, :missing_anthropic_api_key}` outside the `{:model_error, _}`
  wrap — deterministic fallback with `fallback_reason` metadata and **no**
  `runtime_error` event, byte-for-byte the current OpenAI missing-key
  behavior.

---

## Implementation Units

### U1. Invisible-but-audited platform superadmins (AAI-34)

**Goal:** Platform staff exist in every appliance but never appear in
customer user management, cannot be hijacked via self-serve reset, and
their logins are audited.

**Requirements:** R1, R2, R3, R4, R10

**Dependencies:** none

**Files:**
- `lib/andnative_ai/accounts.ex` (`list_customer_users/0`; superadmin-aware `delete_user/1`; reset-delivery skip for superadmins; `rotate_superadmin_password` helper for `Release`)
- `lib/andnative_ai/release.ex` (`rotate_superadmin_password/1` — the out-of-band rotation path R10 requires)
- `lib/andnative_ai_web/live/admin/users_live.ex` (stream customer users; server-side guards on delete/resend targeting superadmin ids)
- `lib/andnative_ai_web/live/user_forgot_password_live.ex` or the delivery path in `lib/andnative_ai/accounts.ex` (superadmin reset exclusion — keep the no-enumeration property: response is identical either way)
- `lib/andnative_ai_web/controllers/user_session_controller.ex` (record `platform_access` on superadmin login)
- `lib/andnative_ai/runtime/audit_event_kinds.ex` (register `platform_access`, governance)
- `priv/repo/seeds.exs` (platform slots per KTD2, ordered before SEED_ADMIN)
- `scripts/provision-appliance.sh` + `deploy/appliance.env.template` (platform slots; reject admin_email colliding with platform emails; `QUIET_CREDENTIALS`)
- `test/andnative_ai/accounts_test.exs`, `test/andnative_ai_web/live/admin/users_live_test.exs` (extend)

**Approach:** Per KTD2/KTD3/KTD4. Reset exclusion happens at the
delivery function (no email sent for superadmins) so the HTTP response
stays indistinguishable (no account enumeration).

**Test scenarios:**
- `list_customer_users/0` excludes superadmins; `list_users/0` includes them.
- Deleting the last non-superadmin active user returns `{:error, :last_user}` even when superadmins exist.
- Superadmin rows never render on `/admin/users`; crafted delete/resend events targeting a superadmin id are no-ops.
- Requesting a password reset for a superadmin email sends nothing and returns the same flash as any other email (no enumeration); an ordinary admin still receives a reset.
- Superadmin login records `platform_access` with the actor email; admin login records nothing.
- Seeds: a new platform email registers with the slot password and role superadmin; an existing user is promoted to superadmin but its password is untouched; re-running is idempotent.
- `Release.rotate_superadmin_password/1` sets a new password for a platform account (unit-test the Accounts function).

**Verification:** full suite green; post-deploy: `/admin/users` on the
demo box hides all three existing superadmins (`m.fahle@gmail.com`,
`marcel@boldvideo.com`, `matthewosullivan87@gmail.com` — already
promoted there), and a superadmin login shows on the control plane.

### U2. Provision workflow + appliance ops recipes (AAI-33 phase A)

**Goal:** Form-based, logged appliance provisioning; one-command
appliance upgrades that actually converge topology, not just code.

**Requirements:** R5, R6

**Dependencies:** U1 (script seeds platform admins)

**Files:**
- `.github/workflows/provision-appliance.yml` (new)
- `justfile` (`appliance-ls`, `appliance-upgrade slug` only — no `appliance-provision` recipe; provisioning is the R5 workflow or direct script use)
- `scripts/provision-appliance.sh` (`QUIET_CREDENTIALS`; **domain format validation** — hostname charset + at least one dot — making "validation stays in the script" true; failure output prints exact SSH cleanup commands for a stranded half-provision)
- `docs/provisioning.md` (both paths; `/opt/appliances` ownership precondition; partial-failure recovery; upgrade semantics)

**Approach:** Workflow mirrors `deploy-main.yml` (KTD5): `permissions:
contents: read`, inputs via env, fail-fast writability check on
`/opt/appliances`, generous timeout (30 min — cold build + 5-min health
wait), job summary = go-live checklist minus secrets, and on failure the
summary carries the script's cleanup commands (the retire workflow
remains deferred; a failed first dispatch must not strand the slug).
`appliance-upgrade` **re-copies `deploy/appliance.compose.yml` over the
appliance's `compose.yml`** (repo file is canonical topology; `$BASE/.env`
is the only per-appliance state) before `up -d --build`; new template
variables are called out as a manual `.env` step in docs.
`appliance-ls` scans `/opt/appliances/*/` — deliberately not `fleet.yml`.

**Execution note:** Workflow YAML can't be CI-tested here; verify by
`bash -n`, `just --list`, and a live dispatch after merge.

**Test scenarios:** Test expectation: none — CI/ops configuration. The
script's new domain-validation guard is exercised by invocation
(`bash -n` + a negative manual call), not the Elixir suite.

**Verification:** `bash -n` clean; `just --list` parses; live dispatch
post-merge provisions a real appliance (this is also the acceptance test
for the partial-failure summary if it fails).

### U3. Provider inference + Anthropic client (AAI-32)

**Goal:** `ModelPolicy` knows which provider serves a model; an
Anthropic client exists with the OpenAI client's exact contract.

**Requirements:** R7, R8

**Dependencies:** none

**Files:**
- `lib/andnative_ai/runtime/model_policy.ex` (add `provider_for/1`)
- `lib/andnative_ai/runtime/anthropic_client.ex` (new; `api_key` arrives in the request map, mirroring `OpenAIClient` — no env reads in the client)
- `deploy/appliance.env.template` (+ commented `# ANTHROPIC_API_KEY=` in Providers; go-live checklist mentions it)
- `test/andnative_ai/runtime/model_policy_test.exs` (extend)

**Approach:** Per KTD6. Client returns
`{:error, {:unexpected_response, status}}` on shape drift.

**Patterns to follow:** `OpenAIClient`'s request-map contract and config
indirection (`:anthropic_client` app env for test fakes); `Req` usage in
`lib/andnative_ai/slack/client.ex`.

**Test scenarios:**
- `provider_for/1`: `claude-opus-4-8` → `:anthropic`; `gpt-5.6-terra`, `o4-mini` → `:openai`; nil-safe default `:openai`.
- Request mapping: system/instructions, user input, max_tokens land in the right fields (assert via request-building function or injected fake transport).
- Non-200/unexpected body → `{:error, {:unexpected_response, _}}`.

**Verification:** unit tests green.

### U4. Route chat + write through the resolved provider (AAI-32)

**Goal:** Model policy selects the provider at runtime; failures degrade
exactly like today's OpenAI failures (KTD8).

**Requirements:** R8, R9

**Dependencies:** U3

**Files:**
- `lib/andnative_ai/runtime/open_claw.ex` (route by provider; env read + placeholder guard for the anthropic key at the call site, mirroring the OpenAI branch)
- `lib/andnative_ai/actions/handlers/write.ex` (same; `provider:` label from resolved provider)
- `lib/andnative_ai_web/live/admin/agents_live.ex` (policy panel hint per KTD7)
- `test/andnative_ai/runtime/open_claw_test.exs`, `test/andnative_ai/writing_actions_test.exs` (extend)

**Approach:** Resolve model → `provider_for/1` → pick client module +
key env at the call site. Missing/placeholder anthropic key short-circuits
per KTD8 (fallback + `fallback_reason`; no `runtime_error` event —
matching OpenAI exactly). Client HTTP errors flow through
`{:error, {:model_error, reason}}` as today. Known inert edge:
`agent_config/1` writes the resolved chat model into the OpenClaw JSON
config; a `claude-*` value there is unread by any consumer today (noted,
not fixed).

**Test scenarios:**
- Agent with `model_policy: %{"write" => "claude-opus-4-8"}` + fake anthropic client: write action calls the anthropic fake; provider metadata reads `anthropic/claude-opus-4-8`.
- Chat with base model `gpt-5.6-terra`: openai fake called (unchanged).
- Anthropic-routed model with no `ANTHROPIC_API_KEY`: deterministic fallback answer; `answer_generated` event carries `fallback_reason`; **no** `runtime_error` event (KTD8).
- Placeholder anthropic key (`replace-me`) short-circuits identically.

**Verification:** full suite green. Post-deploy: (negative) Claude
override with no key → honest fallback on the audit trail; (positive,
end-to-end — the outcome AAI-32 exists for) once `ANTHROPIC_API_KEY` is
set on the box, a `write:` action with a Claude override produces a
model-generated draft with `anthropic/<model>` provider metadata. If no
key is available at ship time, the positive check is recorded as pending
in the PR body rather than silently skipped.

---

## Scope Boundaries

- **In scope:** the three tickets above, one PR, deployed to the demo box.
- **Deferred to Follow-Up Work:** AAI-34 phase 2 (break-glass SSO);
  AAI-33 phase B (fleet console); retire/teardown workflow; `fleet.yml`
  inventory automation; classify/situate provider routing (KTD7);
  backfilling platform accounts onto already-provisioned appliances
  (none exist yet beyond the demo box, where the accounts already exist).
- **Outside scope:** billing, Kubernetes, per-agent Slack apps.

## Risks & Dependencies

- **Fleet-wide account takeover via self-serve reset (P0, security
  review):** mitigated by R10 (reset exclusion) + out-of-band rotation
  via `Release.rotate_superadmin_password/1`.
- **CI credential leakage:** under `QUIET_CREDENTIALS` the script never
  prints secrets, so there is no runtime secret in workflow output to
  mask; the workflow additionally avoids echoing the rendered `.env`.
- **Partial provisioning failure:** `.env` is written first, so a failed
  build/health-wait strands the slug behind the already-provisioned
  guard; the workflow's failure summary prints exact cleanup commands
  (full retire workflow deferred).
- **Deploy-user privileges:** `/opt/appliances` ownership is a stated
  precondition with a fail-fast check; first dispatch surfaces it
  loudly, not as a half-created directory.
- **Anthropic response-shape drift:** `{:error, {:unexpected_response, _}}`
  → existing fallback path.
- Seeds run only when explicitly invoked (release entrypoint runs
  migrations on boot, not seeds); platform slots are idempotent either
  way, so re-invocation is safe.

## Assumptions

- Platform staff emails are fixed (`m.fahle@gmail.com`,
  `matthewosullivan87@gmail.com`), baked as provision-script defaults,
  overridable via env.
- `anthropic-version: 2023-06-01` remains the stable Messages API header
  (not re-fetched in pipeline mode).
- The demo appliance already has its three superadmins promoted; it is
  not re-seeded by this train.

## Definition of Done

- All four units implemented on one branch, three logical commits.
- `DATABASE_PORT=55432 mix precommit` green.
- PR opened, Copilot review addressed (fix or reasoned pushback), merged,
  auto-deploy healthy.
- Superadmins invisible at `/admin/users` on prod; `platform_access`
  events visible after a superadmin login; reset-flow exclusion verified
  by test.
- AAI-32 positive end-to-end check run (or recorded as pending on the PR
  if no `ANTHROPIC_API_KEY` is available).
