---
artifact_contract: ce-unified-plan/v1
artifact_readiness: implementation-ready
execution: code
product_contract_source: ce-plan-bootstrap
origin: "User request: wire Resend as the transactional email provider (https://resend.com/llms.txt). Builds on the Swoosh mailer added in PR #4."
plan_type: feat
depth: lightweight
created: 2026-06-28
---

# feat: Send transactional email via Resend

**Target repo:** andnative_ai

Wire **Resend** as the production transactional-email provider for the admin auth flows (password reset, invitations), using the existing Swoosh mailer abstraction. No application email code changes — `UserNotifier` already builds `Swoosh.Email`s; this swaps the production adapter to `Swoosh.Adapters.Resend`, selected from the environment.

---

## Problem Frame

PR #4 added the Swoosh mailer with a safe-by-default adapter chain (Local in dev/test; SMTP via `MAILER_ADAPTER=smtp`; Local fallback when unconfigured). It does not actually deliver mail in production until a provider is wired. The user wants **Resend** as that provider, driven by `RESEND_API_KEY` so reset/invite links are really delivered.

**In scope:** production adapter selection for Resend, the Swoosh API client it requires, docs (key, domain verification, sandbox sender), and a test that the Resend path produces the correct API request.

**Out of scope:** changing email content/`UserNotifier`, dev/test delivery (stay on Local/Test), Resend batch/templates/webhooks/contacts.

---

## Requirements

- **R1** — When `RESEND_API_KEY` is set in production, email is delivered via `Swoosh.Adapters.Resend` using that key. This takes precedence over `MAILER_ADAPTER=smtp`; with neither set, prod still falls back to the Local adapter (no crash).
- **R2** — The Swoosh API client required by the Resend adapter is configured (the app already depends on `req`, so use `Swoosh.ApiClient.Req`). Dev/test (Local/Test adapters) are unaffected and need no API client.
- **R3** — The `from` identity is operator-controlled via `MAILER_FROM` and must be a Resend-verified sender (or the `onboarding@resend.dev` sandbox during testing). No secret (`RESEND_API_KEY`) is committed to code or docs.
- **R4** — Deploy docs explain: creating a Resend API key, verifying a sending domain (or using `onboarding@resend.dev`), and the `RESEND_API_KEY` / `MAILER_FROM` env.
- **R5** — A test proves the Resend path: delivering a `UserNotifier` email through the Resend adapter issues a `POST https://api.resend.com/emails` with `Authorization: Bearer <key>` and a body carrying `from`/`to`/`subject`.

---

## Key Technical Decisions

**KTD1 — Use `Swoosh.Adapters.Resend`, not the native Resend SDK.** The app already uses Swoosh and `UserNotifier` builds `Swoosh.Email`s; the Resend adapter (shipped with the installed Swoosh `~> 1.16`) slots in via config alone, preserving the abstraction. The native Resend Elixir SDK would duplicate delivery and bypass Swoosh.

**KTD2 — Auto-select Resend from `RESEND_API_KEY` (no extra flag).** In `config/runtime.exs` (prod), a `cond` selects: `RESEND_API_KEY` present → Resend; else `MAILER_ADAPTER == "smtp"` → SMTP (existing); else → Local fallback. Making the key itself the trigger is the simplest operator UX and keeps the safe-by-default behavior intact.

**KTD3 — `Swoosh.ApiClient.Req` as the API client.** The Resend adapter "requires an API Client"; `req` is already a dependency and `Swoosh.ApiClient.Req` needs no supervision-tree setup (unlike a Finch pool). Set `config :swoosh, :api_client, Swoosh.ApiClient.Req` only on the Resend branch so Local/Test keep `api_client: false`.

**KTD4 — Sender stays env-driven.** Reuse the existing `:mailer_from` / `MAILER_FROM` config. Resend rejects unverified senders, so docs must call out domain verification (or `onboarding@resend.dev`, which only sends to the account owner). No default change needed.

---

## Implementation Units

### U1. Production Resend adapter selection

**Goal:** R1, R2, R3.
**Dependencies:** none.
**Files:** `config/runtime.exs`.
**Approach:** Replace the existing prod `case System.get_env("MAILER_ADAPTER")` block with a `cond`: when `RESEND_API_KEY` is a non-empty string, set `config :swoosh, :api_client, Swoosh.ApiClient.Req` and `config :andnative_ai, AndnativeAi.Mailer, adapter: Swoosh.Adapters.Resend, api_key: <key>`; keep the existing `"smtp"` branch; default to `Swoosh.Adapters.Local`. Leave `config/config.exs` (`api_client: false`, default Local) and `config/test.exs` (Test adapter) unchanged.
**Patterns to follow:** the existing prod mailer block in `config/runtime.exs`; the Resend adapter config example in `Swoosh.Adapters.Resend` moduledoc.
**Test scenarios:** `Test expectation: none — prod-only runtime config; the delivery path it enables is covered by U3 against the adapter directly.`
**Verification:** `mix compile` clean; `config/runtime.exs` reads `RESEND_API_KEY`/`MAILER_FROM` and never embeds a key.

### U2. Resend delivery test (request shaping)

**Goal:** R5.
**Dependencies:** none (tests the adapter + `UserNotifier`, independent of U1's prod-only config).
**Files:** `test/andnative_ai/mailer_resend_test.exs` (new).
**Approach:** In an `async: false` test, install a fake `Swoosh.ApiClient` (implements `post/4`) that forwards `{url, headers, body}` to the test process and returns a `200` with a JSON id; temporarily set `config :swoosh, :api_client` to it and reconfigure `AndnativeAi.Mailer` to `Swoosh.Adapters.Resend` with `api_key: "re_test_123"` (restore both in `on_exit`). Deliver a `UserNotifier.deliver_reset_password_instructions/2` email and assert the captured request.
**Patterns to follow:** the existing `UserNotifier` tests; the `Swoosh.ApiClient` behaviour (`post(url, headers, body, email)`); the Resend adapter (`@base_url "https://api.resend.com"`, `Authorization: Bearer <api_key>`).
**Test scenarios:**
- Delivering a reset email via the Resend adapter posts to a URL under `https://api.resend.com` with an `Authorization: Bearer re_test_123` header.
- The request body (JSON) contains the recipient, the subject, and the reset link text/`from`.
- Restores the prior mailer + api_client config afterward (no leakage into other tests).
**Verification:** `mix test test/andnative_ai/mailer_resend_test.exs` green; the rest of the suite unaffected.

### U3. Deploy docs

**Goal:** R4.
**Dependencies:** U1.
**Files:** `docs/hetzner-demo-deploy.md`.
**Approach:** In the "Email delivery" section, add Resend as the recommended prod provider: create an API key in the Resend dashboard, verify the sending domain (or use `onboarding@resend.dev` for testing, which only delivers to the account owner), then set `RESEND_API_KEY` and `MAILER_FROM` (a verified sender) in `/opt/andnativeai/.env`. Note that setting `RESEND_API_KEY` is all it takes (auto-selected over SMTP), that unset still falls back to Local, and that no key is stored in the repo.
**Patterns to follow:** the existing "Email delivery" subsection.
**Test scenarios:** `Test expectation: none — docs; cross-check env names against U1 and that no secret is present.`
**Verification:** env names match U1; no `RESEND_API_KEY` value present.

---

## Scope Boundaries

### Deferred to Follow-Up Work
- Resend **batch send**, **templates**, **scheduled_at**, **idempotency keys**, **webhooks**, **contacts/audiences** — not needed for two transactional emails.
- **Rate-limit handling / retries** on Resend's default limits — the volume (reset/invite) is tiny; revisit if it grows.

### Out of Scope (non-goals)
- Changing `UserNotifier` content or the dev/test (Local/Test) adapters.
- Switching the whole app to the native Resend SDK.

---

## Risks & Dependencies

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| `from` domain not verified in Resend → sends rejected | Medium | Medium | U3 documents domain verification + the `onboarding@resend.dev` sandbox. |
| API client not configured → Resend adapter raises | Low | High | U1 sets `Swoosh.ApiClient.Req` on the Resend branch; U2 exercises the delivery path. |
| `RESEND_API_KEY` leaking into the repo | Low | High | Env-only; U2 uses a fake `re_test_*`; docs use placeholders. |

**External dependencies:** `swoosh` (`Swoosh.Adapters.Resend`, present), `req` (`Swoosh.ApiClient.Req`, present) — no new deps.

---

## Definition of Done

- R1–R5 satisfied; `mix precommit` green (compile `--warnings-as-errors`, format, full suite incl. the new Resend test).
- Production selects Resend when `RESEND_API_KEY` is set; dev/test unchanged.
- No `RESEND_API_KEY` value in code or docs.
- `docs/hetzner-demo-deploy.md` documents Resend setup; PR opened against `main`.

---

## Verification Contract

1. `mix compile --warnings-as-errors` clean.
2. `mix test test/andnative_ai/mailer_resend_test.exs` proves the Resend request (URL, Bearer auth, body); `mix precommit` green overall.
3. `grep -rn "re_[A-Za-z0-9]" lib config docs` finds no real key (only the test's `re_test_*`).

---

## Sources & Research

- **User-named source:** https://resend.com/llms.txt → https://resend.com/docs/llms.txt. Send API: `POST https://api.resend.com/emails`, `Authorization: Bearer re_…`, JSON `{from,to,subject,html,text,reply_to}`; key prefix `re_`, env `RESEND_API_KEY`; sender domain must be verified, `onboarding@resend.dev` is a sandbox sender restricted to the account owner; default rate limits + a batch endpoint (deferred).
- **Installed adapter:** `Swoosh.Adapters.Resend` (`deps/swoosh`) — `use Swoosh.Adapter, required_config: [:api_key]`, `@base_url "https://api.resend.com"`, `Authorization: Bearer <api_key>`, "requires an API Client" (`Swoosh.ApiClient.Req` available).
- **Codebase:** `config/runtime.exs` (existing prod mailer block), `config/config.exs` (`api_client: false`, `:mailer_from`), `lib/andnative_ai/mailer.ex`, `lib/andnative_ai/accounts/user_notifier.ex`, `docs/hetzner-demo-deploy.md` (Email delivery section).
