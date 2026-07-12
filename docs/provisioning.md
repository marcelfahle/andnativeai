# Provisioning an appliance

One command turns this VM into another customer appliance (Compose-per-
appliance, per the plan in
`docs/plans/2026-07-11-001-appliance-provisioning-and-super-admin.md`):

```sh
scripts/provision-appliance.sh <slug> <domain> <admin-email>
# e.g.
scripts/provision-appliance.sh acme acme.andnative.ai founder@acme.example
```

The script renders `/opt/appliances/<slug>/.env` from
`deploy/appliance.env.template` with freshly generated secrets
(`SECRET_KEY_BASE`, DB and MinIO passwords, `CLOAK_KEY`, a first-admin
password), copies the generic Compose project
(`deploy/appliance.compose.yml`), builds and starts it under its own
project name, waits for health (migrations run on boot), seeds the first
admin, writes a Caddy vhost snippet, and prints the go-live checklist
(DNS, Caddy reload, provider keys, Slack app, superadmin promotion).

Facts worth knowing:

- One VM hosts several appliances side by side: separate Compose projects,
  separate volumes under `/opt/appliances/<slug>/var`, one shared Caddy on
  the `deploy_default` network (`CADDY_NETWORK` to override).
- Re-running for an existing slug refuses to touch anything; retire an
  appliance with `docker compose -p andnative-<slug> down` and move its
  directory away.
- The fleet inventory (which appliances exist, where) stays in the private
  ops repo per the plan — this script is the phase-1 provisioning console.
- Every step maps 1:1 to a future Helm value, so Kubernetes later is a
  mechanical port, not a rethink.
