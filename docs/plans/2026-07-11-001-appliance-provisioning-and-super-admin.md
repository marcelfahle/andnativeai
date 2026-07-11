# Appliance Provisioning & Super-Admin Plan

Status: proposal (2026-07-11). Turns the one-tenant PoC into something a
super-admin can "fire up" per customer. Companion Linear tickets: AAI-19
(super-admin + provisioning console), AAI-20 (single-command appliance
bootstrap), AAI-21 (encrypted secrets), AAI-22 (OpenClaw gateway service
decision).

## Where we are

Deployable today, by hand, once:

- One Hetzner box, one Compose project (`deploy/hetzner-demo.compose.yml`),
  prod release images, Caddy TLS, GitHub Actions auto-deploy from `main`
  (DEC-013).
- App-level auth with invites and a seeded first admin (AAI-18).
- Memory service and OpenClaw adapter run inside the `control-panel` and
  `slack-listener` release; `memory-service` and `openclaw-gateway` Compose
  entries are placeholders for a future service split.
- Slack OAuth per workspace; one platform Socket Mode app token.
- Secrets: `.env` on the box; Slack tokens plaintext in Postgres (DEC-011
  caveat).

What "fire up an appliance" means concretely, per customer:

1. Compute + DNS (`customer.andnative.ai`), TLS.
2. A Compose project (or namespace) with Postgres/pgvector, app release,
   Slack listener, volumes.
3. An `.env` from a template: `SECRET_KEY_BASE`, DB password, `PHX_HOST`,
   Slack app credentials, LLM key.
4. Migrations + seeded first admin (customer email, forced password change).
5. The tenant row (the appliance stays one-tenant; the *fleet* is many
   appliances — this keeps the isolation story customers buy).

## Deployment target options

### A. Compose-per-appliance on shared or dedicated VMs (recommended now)

One VM can host several appliances (separate Compose projects, separate
volumes, one Caddy). Dedicated VM for customers who pay for hard isolation.

- - Matches what exists; the Hetzner demo is appliance #1.
- - Cheap (EUR ~5-15/appliance), explainable to SMEs ("your box").
- - A provisioning script can do end-to-end bootstrap in minutes (AAI-20).
- - Fleet operations (upgrades across N boxes) stay manual-ish: solvable
  with the existing rsync+Actions pattern iterated over an inventory file.

### B. Kubernetes (namespace-per-appliance)

- - Fleet upgrades, secrets, and scaling become declarative; one `helm
  upgrade` rolls every appliance.
- - Real answer at ~20+ appliances or when SLAs demand self-healing.
- - Operational tax (cluster, CNI, storage classes, cert-manager) is not
  justified for < 10 customers and one operator; hides the "appliance"
  story that sells.

### C. Managed PaaS (Fly.io machines / Render)

- - Fastest provisioning API story.
- - EU data residency and "runs in your environment" positioning get
  murkier; per-app Postgres with pgvector adds cost.

Recommendation: stay on A through the first paying customers, build the
provisioning script + inventory now, and design it so each step maps 1:1 to
a future Helm chart value (B becomes a mechanical port, not a rethink).

## Super-admin model

Two-level model, deliberately boring:

- **Platform super-admin (Marcel/Matt)** — operates the fleet: create
  appliance, see health, rotate secrets, retire appliance. Lives *outside*
  customer appliances (a small `fleet` console or, phase 1, the
  provisioning CLI + an inventory file in a private repo).
- **Appliance admin (customer)** — the existing users/invite system inside
  their appliance. Already shipped.

Phase 1 (cheap, now):
- `scripts/provision-appliance.sh <slug> <domain> <admin-email>` renders
  `.env` + Compose project + Caddy vhost from templates, runs migrations,
  seeds the admin, prints the invite link. Inventory = a checked-in
  `fleet.yml` in a private ops repo.
- Add `role` column on users (`admin` | `superadmin`) so platform staff
  accounts inside an appliance are distinguishable and future
  platform-only pages have something to check. No UI change yet.

Phase 2 (when >3 appliances):
- Tiny fleet console (separate Phoenix app or a `/fleet` area gated to
  `superadmin` + allowlisted appliance): list appliances from inventory,
  health pings against each `/admin/control-plane` healthcheck, links.

Phase 3 (with real customer count): move inventory into a database, wire
provisioning through the console, evaluate Kubernetes (option B).

## Hardening that must land before customer #1

- Encrypted secrets at rest for Slack tokens + OAuth client secret
  (Cloak/`cloak_ecto`, key from env) — AAI-21.
- Per-appliance Slack app (or documented shared-app implications): Socket
  Mode app token is currently platform-level.
- Backups: nightly `pg_dump` + `var/sources` to object storage; restore
  drill documented.
- Decide the placeholder services' fate: either extract the OpenClaw
  gateway into the real container (AAI-22) or delete the placeholders from
  Compose so the deploy surface is honest.

## Explicit non-goals right now

- Multi-tenant single deployment (the appliance isolation *is* the
  product story).
- Kubernetes before the fleet justifies it.
- Billing/metering.
