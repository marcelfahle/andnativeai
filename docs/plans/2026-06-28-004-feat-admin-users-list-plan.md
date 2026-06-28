---
artifact_contract: ce-unified-plan/v1
artifact_readiness: implementation-ready
execution: code
product_contract_source: ce-plan-bootstrap
origin: "User request: admin user list with delete + resend-invite. Builds on the account-management auth (PR #4) and Resend email (PR #5), both merged to main."
plan_type: feat
depth: standard
created: 2026-06-28
---

# feat: Admin users list (delete + resend invite)

**Target repo:** andnative_ai

An authenticated admin page that lists all users with their status (Active / Invited), and lets an admin **delete** a user or **resend the invitation** to a still-pending invitee. Motivation: two users were invited before Resend was configured, so their invite emails never sent — this gives a one-click resend now that Resend is live.

---

## Problem Frame

The auth system can invite users (`/admin/users/invite`) and delete them (`Accounts.delete_user/1`), but there is **no UI to see who exists or to re-send a stuck invitation**. Invitees created while email delivery was misconfigured are stranded: they exist with `confirmed_at: nil` (status "Invited") and a now-stale/undelivered invite token, with no admin path to recover.

**In scope:** a `/admin/users` list (email, status, joined), per-row **Delete** (honoring the last-user/self guards) and **Resend invite** (pending users only).

**Out of scope:** editing users, roles/permissions, bulk actions, pagination/search (user count is tiny).

---

## Requirements

- **R1** — `/admin/users` (authenticated) lists all users ordered by email, showing email, **status** (Active when `confirmed_at` is set, else Invited), and joined date.
- **R2** — An admin can **delete** a user from the list. Deletion honors the existing guards: the last active user cannot be deleted (`{:error, :last_user}` → clear flash), and an admin **cannot delete their own account** from the list.
- **R3** — An admin can **resend the invitation** to a pending (Invited) user: a fresh invite token is generated (old invite tokens for that user are invalidated) and the invitation email is sent via the configured mailer (Resend in prod). Resending to an already-Active user is rejected.
- **R4** — The page is reachable from the admin nav, and the existing invite form (`/admin/users/invite`) is reachable from it.

---

## Key Technical Decisions

**KTD1 — `confirmed_at` is the status signal (reuse the existing model).** A user with `confirmed_at` set is "Active"; `nil` is "Invited" (an unaccepted invite stub). This is already the meaning established by `register_user`/`accept_invitation`/`delete_user`; the list and resend gate reuse it — no schema or status column needed.

**KTD2 — `resend_user_invitation/2` rotates the invite token.** For a `confirmed_at: nil` user, delete the user's existing `"invite"` tokens, build a fresh hashed invite token, and deliver via `UserNotifier`. This invalidates any stale link and matches the one-active-token expectation. A `confirmed_at`-set user returns `{:error, :already_active}` (nothing to resend). `invite_user/2` and `resend_user_invitation/2` share a private token-build-and-deliver helper.

**KTD3 — Delete guards live in the context; the UI adds self-delete.** `Accounts.delete_user/1` already refuses the last active user and always allows deleting an unconfirmed stub. The LiveView additionally blocks deleting the **current** user (hides the action for that row and guards the event), since self-deletion from an admin list is a foot-gun and would orphan the acting session.

**KTD4 — Render with the existing `<.table>` core component** and `phx-click` actions with `data-confirm`, mirroring the existing admin LiveViews — no new UI primitives.

---

## Implementation Units

### U1. Accounts: list, fetch, and resend-invitation

**Goal:** R1, R2 (fetch), R3.
**Dependencies:** none.
**Files:** `lib/andnative_ai/accounts.ex`, `test/andnative_ai/accounts_test.exs`.
**Approach:**
- `list_users/0` — `Repo.all(from u in User, order_by: [asc: u.email])`.
- `get_user!/1` — re-add `Repo.get!(User, id)` (a caller exists now).
- Extract a private `deliver_new_invitation(user, invite_url_fun)` that builds + inserts an `"invite"` token and calls `UserNotifier.deliver_invitation`; refactor `invite_user/2` to use it (keeping its orphan-cleanup on mail failure).
- `resend_user_invitation/2` — for a `%User{confirmed_at: nil}`: `Repo.delete_all` the user's `"invite"` tokens, then `deliver_new_invitation`; on mail error return `{:error, reason}` (do **not** delete the existing user). For a `%User{}` (active): `{:error, :already_active}`.
**Patterns to follow:** existing `invite_user/2`, `UserToken.by_user_and_contexts_query/2`, `UserNotifier.deliver_invitation/2`, the `Accounts` getter style.
**Test scenarios:**
- `list_users/0` returns active and invited users.
- `resend_user_invitation/2` on a pending user sends an invitation email (Test adapter) and rotates the token — the previously-issued invite token no longer resolves, the new one does.
- `resend_user_invitation/2` on an active user returns `{:error, :already_active}` and sends no email.
- `invite_user/2` still works and still cleans up on mail failure (regression).
**Verification:** `mix test test/andnative_ai/accounts_test.exs` green.

### U2. Admin users LiveView + route + nav

**Goal:** R1, R2, R4.
**Dependencies:** U1.
**Files:** `lib/andnative_ai_web/live/admin/users_live.ex` (new), `lib/andnative_ai_web/router.ex`, `lib/andnative_ai_web/components/layouts.ex`, `test/andnative_ai_web/live/admin/users_live_test.exs` (new).
**Approach:**
- `Admin.UsersLive` at `live "/admin/users"` inside the authenticated `live_session :require_authenticated_user`. Header with an "Invite a user" link to `/admin/users/invite`. A `<.table rows={@users}>` with columns Email, Status (Active/Invited badge), Joined; an actions column with **Resend invite** (only when `is_nil(user.confirmed_at)`) and **Delete** (only when `user.id != @current_user.id`), both `phx-click` with `data-confirm`.
- `handle_event("delete", %{"id" => id}, …)`: refuse if `id == current_user.id` (flash); else `Accounts.delete_user(Accounts.get_user!(id))` → flash on `{:ok}` / `{:error, :last_user}`; reload list.
- `handle_event("resend", %{"id" => id}, …)`: `Accounts.resend_user_invitation(Accounts.get_user!(id), &url(~p"/users/invite/#{&1}"))` → flash on `{:ok}` / `{:error, :already_active}` / `{:error, _}`; reload list.
- Nav: replace the standalone "Invite" link in `Layouts.app` with a "Users" link to `/admin/users` (invite stays reachable from the list page).
**Patterns to follow:** existing admin LiveViews (`<Layouts.app flash={@flash} current_user={@current_user}>`), `Admin.UserInviteLive` (flash + `url(~p"/users/invite/#{&1}")`), `core_components` `table/1`, `button/1`.
**Test scenarios:**
- Authenticated admin sees the list with the seeded/active user and an invited user, with correct status.
- Unauthenticated GET `/admin/users` → redirect to `/login`.
- Delete a deletable user removes it from the list; deleting the last active user is refused with a flash; the current user's row has no delete action (and the event is guarded).
- Resend invite on a pending user shows a success flash and sends an email (Test adapter); the resend action is absent on active rows.
**Verification:** `mix test test/andnative_ai_web/live/admin/users_live_test.exs` green; `mix precommit` green overall.

### U3. Docs

**Goal:** R4.
**Dependencies:** U2.
**Files:** `docs/hetzner-demo-deploy.md`.
**Approach:** In the admin-auth section, note the **Users** admin page (`/admin/users`) for listing users, deleting, and resending invitations — the in-app way to recover invitees whose original email failed.
**Test scenarios:** `Test expectation: none — docs.`
**Verification:** route names match U2.

---

## Scope Boundaries

### Deferred to Follow-Up Work
- Editing a user's email, roles/permissions, bulk delete, pagination/search.
- Expiring/cleaning up abandoned invite stubs.
- An audit entry for admin delete/resend actions (the governance-audit timeline could record these later).

### Out of Scope (non-goals)
- Changing the invite/accept/reset flows themselves.

---

## Risks & Dependencies

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Admin deletes themselves / the last admin → lockout | Low | High | KTD3: context refuses the last active user; the LiveView blocks self-delete (no action + event guard). |
| Resend leaves a stale + a new token both valid | Low | Low | KTD2 deletes the user's existing `"invite"` tokens before issuing a new one. |
| Resend mail failure orphans state | Low | Low | Resend operates on an existing user and does not create/delete it; a mail error is reported, the user is untouched. |

**External dependencies:** the merged account-management context (`Accounts`, `UserToken`, `UserNotifier`) and the Resend mailer — all on `main`.

---

## Definition of Done

- R1–R4 satisfied; `mix precommit` green (compile `--warnings-as-errors`, format, full suite incl. the new tests).
- The last active user and the current user cannot be deleted from the list; resend works only for pending users and rotates the token.
- PR opened against `main`.

---

## Verification Contract

1. `mix compile --warnings-as-errors` clean.
2. `mix test` — full suite green incl. `accounts_test` (list/resend) and `users_live_test` (list/delete/resend/auth).
3. Manual smoke (dev): visit `/admin/users`, resend an invite to a pending user (email captured by the dev preview adapter), delete a non-self/non-last user.

---

## Sources & Research

- **Codebase (on main):** `lib/andnative_ai/accounts.ex` (`invite_user/2`, `delete_user/1` active/stub clauses, `get_user_by_invite_token/1`, `update_password_multi`, `by_user_and_contexts_query`), `lib/andnative_ai/accounts/user_notifier.ex` (`deliver_invitation/2`), `lib/andnative_ai_web/live/admin/user_invite_live.ex`, `lib/andnative_ai_web/router.ex` (authenticated `live_session`), `lib/andnative_ai_web/components/layouts.ex` (nav), `lib/andnative_ai_web/components/core_components.ex` (`table/1`, `button/1`), `test/support/conn_case.ex` (`register_and_log_in_user`), `test/support/fixtures/accounts_fixtures.ex` (`extract_user_token`).
