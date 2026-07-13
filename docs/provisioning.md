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

## Form-based provisioning (GitHub Actions)

The `Provision Appliance` workflow (`workflow_dispatch`) is the phase-A
console: fill slug/domain/admin-email in the GitHub UI and every run is
attributable and logged. It SSHes with the existing deploy key and runs
the script with `QUIET_CREDENTIALS=true`, so generated passwords never
appear in CI logs — they live only in `/opt/appliances/<slug>/.env`.

One-time precondition: the deploy user must own the appliances root
(`sudo mkdir -p /opt/appliances && sudo chown andnative-deploy /opt/appliances`).
The workflow fails fast with that exact instruction if it is missing.

If a run fails mid-provision (e.g. the health wait), the log ends with
the exact cleanup commands; run them over SSH before re-dispatching —
the already-provisioned guard refuses to overwrite a half-built slug.

## Upgrading appliances

Provisioned appliances build from the repo checkout at provision time and
do not follow `main` automatically. After a deploy:

```sh
just appliance-ls
just appliance-upgrade acme
```

`appliance-upgrade` re-copies `deploy/appliance.compose.yml` (the repo
file is the canonical topology; the appliance's `.env` is its only local
state) and rebuilds. If a release added new required `.env` variables
(see `deploy/appliance.env.template`), add them manually first.

## Platform staff access

Every provisioned appliance seeds `m.fahle@gmail.com` and
`matthewosullivan87@gmail.com` as superadmins with per-appliance
passwords (in the appliance `.env`). They are invisible in the customer's
user management, excluded from self-serve password reset, and their
logins land on the governance audit trail. Rotate a password with:

```sh
docker compose -p andnative-<slug> --env-file /opt/appliances/<slug>/.env \
  -f /opt/appliances/<slug>/compose.yml exec control-panel \
  ./bin/andnative_ai eval 'AndnativeAi.Release.rotate_superadmin_password("m.fahle@gmail.com")'
```
