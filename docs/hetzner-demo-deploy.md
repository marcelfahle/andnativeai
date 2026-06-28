# Hetzner Demo Deploy

Current demo host:

- Host: `bold-importer`
- IP: `91.99.49.152`
- Domain: `andnativeai.marcelfahle.net`
- App path: `/opt/andnativeai`

## Shape

This deployment shares the importer box but isolates the PoC:

- Separate repo directory: `/opt/andnativeai`
- Separate Compose project
- Private Postgres/Redis/MinIO
- Phoenix production release image (`MIX_ENV=prod`), not `mix phx.server`
- `control-panel` attached to Caddy's `deploy_default` network
- Caddy terminates TLS; the admin UI is protected by app-level login. Caddy
  basic auth is now optional (see [Admin authentication](#admin-authentication))

The importer already owns host port `4000`, so this PoC must not publish host
port `4000`.

## Auto Deploy From Main

GitHub Actions deploys every push to `main`. This is the normal deploy path.

Workflow:

1. Check out `main`.
2. Rsync tracked application files to `/opt/andnativeai`.
3. Preserve server-only state by excluding `.env`, `var/`, `_build`, `deps`,
   and generated `priv/static/assets`.
4. Build the release Docker target and restart the Compose stack.
5. Force-recreate `control-panel` and `slack-listener` so the running release
   processes pick up the rebuilt image.
6. Verify the app is healthy: an unauthenticated request to an admin route
   (e.g. `/admin/agents`) redirects to `/login`, and a logged-in session reaches
   the admin UI. If Caddy basic auth is kept as an outer belt, the
   unauthenticated request returns `401` at the Caddy layer first.

Required GitHub secret:

- `HETZNER_DEPLOY_SSH_KEY`: private key for the server user
  `andnative-deploy`.

Server setup:

- User: `andnative-deploy`
- App path: `/opt/andnativeai`
- User must be able to write app files and run Docker Compose.
- `/opt/andnativeai/.env` must contain production-only secrets:

  ```sh
  SECRET_KEY_BASE=<generated with mix phx.gen.secret>
  POSTGRES_PASSWORD=<generated with openssl rand -hex 32>
  MINIO_ROOT_PASSWORD=<generated with openssl rand -hex 32>
  RESEND_API_KEY=re_...                         # optional until email is needed
  MAILER_FROM=no-reply@andnativeai.marcelfahle.net
  ```

`SECRET_KEY_BASE`, `POSTGRES_PASSWORD`, and `MINIO_ROOT_PASSWORD` are required
for production deploys. The deploy workflow rejects missing, placeholder, or
short values before rebuilding the stack. Keep the generated Postgres and MinIO
passwords alphanumeric; `openssl rand -hex 32` satisfies that requirement.

Manual workflow dispatch:

```sh
gh workflow run deploy-main.yml --ref main
```

## Manual Deploy Or Update

From local repo:

```sh
rsync -az --delete \
  --exclude .git \
  --exclude .DS_Store \
  --exclude .env \
  --exclude _build \
  --exclude deps \
  --exclude priv/static/assets \
  --exclude var \
  -e "ssh -i ~/.ssh/id_ed25519_mf2024" \
  ./ root@91.99.49.152:/opt/andnativeai/
```

On the server:

```sh
cd /opt/andnativeai/deploy
docker compose --env-file ../.env -p andnativeai -f hetzner-demo.compose.yml up -d --build
```

## Production Runtime

The Hetzner stack runs an OTP release from the Docker `release` target:

- `control-panel` runs `/app/bin/control-panel`, which creates the configured
  database when absent, runs migrations, runs `priv/repo/seeds.exs`, and starts
  `/app/bin/server` with `PHX_SERVER=true`.
- `slack-listener` runs `/app/bin/slack-listener` with
  `SERVICE_ROLE=slack-listener`. It uses the same release image but does not
  start the HTTP server.
- The release reads database connection parts, `SECRET_KEY_BASE`, `PHX_HOST`,
  `PORT`, Slack credentials, OpenAI credentials, and mailer credentials from
  env.
- Production services do **not** bind-mount the repo, `deps`, or `_build` into
  `/app`.
- Production Compose commands must include `--env-file ../.env` so Compose can
  interpolate server-only secrets without committing them.

Useful release commands:

```sh
cd /opt/andnativeai/deploy
docker compose --env-file ../.env -p andnativeai -f hetzner-demo.compose.yml exec control-panel ./bin/migrate
docker compose --env-file ../.env -p andnativeai -f hetzner-demo.compose.yml exec control-panel ./bin/andnative_ai eval "AndnativeAi.Release.seed()"
```

Rotate the Postgres role password after changing `POSTGRES_PASSWORD`:

```sh
cd /opt/andnativeai/deploy
set -a
. ../.env
set +a
docker compose --env-file ../.env -p andnativeai -f hetzner-demo.compose.yml up -d postgres
docker compose --env-file ../.env -p andnativeai -f hetzner-demo.compose.yml exec -T \
  -e NEW_POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
  postgres sh -lc 'psql -U postgres -d postgres -v ON_ERROR_STOP=1 -c "ALTER USER postgres WITH PASSWORD '\''$NEW_POSTGRES_PASSWORD'\'';"'
```

### One-time database preservation

The original demo stack used the database name `andnative_ai_dev`. The production
release uses `andnative_ai_prod`. Before the first prod-release deploy on an
existing host, copy the old database once if it contains data you want to keep:

```sh
cd /opt/andnativeai/deploy
docker compose --env-file ../.env -p andnativeai -f hetzner-demo.compose.yml up -d postgres
docker compose --env-file ../.env -p andnativeai -f hetzner-demo.compose.yml exec postgres sh -lc \
  'if psql -U postgres -tc "SELECT 1 FROM pg_database WHERE datname = '\''andnative_ai_prod'\''" | grep -q 1; then
     echo "andnative_ai_prod already exists; inspect it before copying"
   else
     createdb -U postgres andnative_ai_prod
     pg_dump -U postgres andnative_ai_dev | psql -U postgres andnative_ai_prod
   fi'
```

Skip the copy only when starting with a clean production database is acceptable.
The release startup still runs migrations afterward, so copied data is upgraded
to the current schema.

## Caddy

The Caddyfile is at `/opt/bold_mcp/deploy/Caddyfile`.

The durable auth boundary now lives in the Phoenix app (see
[Admin authentication](#admin-authentication)), so Caddy basic auth is
**optional**. The simplest vhost just terminates TLS and proxies:

```caddyfile
andnativeai.marcelfahle.net {
  encode zstd gzip
  reverse_proxy andnative-control-panel:4000
}
```

If you want to keep basic auth as an optional outer belt during the transition,
add a `basic_auth` block. Generate hashes with `caddy hash-password` and store
them only in the Caddyfile on the server — never commit passwords or hashes:

```caddyfile
andnativeai.marcelfahle.net {
  encode zstd gzip
  basic_auth {
    # <user> <bcrypt-hash from `caddy hash-password`>
  }
  reverse_proxy andnative-control-panel:4000
}
```

Reload Caddy:

```sh
docker exec bold-mcp-caddy caddy reload --config /etc/caddy/Caddyfile
```

## Admin authentication

The admin UI uses app-level email/password login. Users live in the `users`
table, and every `/admin/*` route (plus `/slack/install`) requires a logged-in
session. `/slack/oauth/callback` stays public so Slack can complete installs.

The release `control-panel` entrypoint runs `AndnativeAi.Release.create/0`,
`AndnativeAi.Release.migrate/0`, and `AndnativeAi.Release.seed/0` on every
start, so the `users` table and admins are provisioned automatically on deploy.

### First login

The first admin, **`m.fahle@gmail.com`**, is seeded by a database migration with
the default password **`changeme123`**. Log in and change it immediately at
**Settings** (`/users/settings`).

> `changeme123` is a one-time bootstrap value, not a real secret — anyone who
> reaches the login page can use it until it is changed. Change it on first
> login, and use the invite flow for everyone else.

### Adding users

The **Users** page (`/admin/users`, in the nav) lists everyone with their status
(Active vs. Invited), and lets you delete a user or **resend an invitation** to a
still-pending invitee — useful for recovering invites whose original email failed
to send. You can't delete your own account or the last remaining admin.

- **Invite (recommended):** from the Users page (or `/admin/users/invite`), enter
  the person's email. They receive a link to set their own password and activate.
  Requires email delivery (see below). If their first invite didn't arrive, use
  **Resend invite** on the Users page once email is configured.
- **Env seed:** set `SEED_MATT_EMAIL` and `SEED_MATT_PASSWORD` (or any other
  pair) in `/opt/andnativeai/.env`; the entrypoint seeds them on the next
  deploy. No password is ever stored in the repo. Seeding is idempotent — an
  existing user is left untouched, and a user with no password env is skipped.
  To seed without a restart:

  ```sh
  docker compose -p andnativeai -f /opt/andnativeai/deploy/hetzner-demo.compose.yml \
    exec control-panel ./bin/andnative_ai eval "AndnativeAi.Release.seed()"
  ```

### Resetting a forgotten password

Use **Forgot your password?** on the login page (`/users/reset-password`); it
emails a one-day reset link (requires email delivery). With no email configured,
an operator can set a new password directly — `reset_user_password/2` does not
require the current password:

```sh
docker compose -p andnativeai -f /opt/andnativeai/deploy/hetzner-demo.compose.yml \
  exec control-panel \
  ./bin/andnative_ai eval 'u = AndnativeAi.Accounts.get_user_by_email("user@example.com"); AndnativeAi.Accounts.reset_user_password(u, %{password: "a new strong password"})'
```

The last remaining user can never be deleted, so the app can't be locked out.

### Email delivery

Password reset and invitations send email via Swoosh. The adapter is selected
from the environment in **every run mode except `:test`** — including the
deployed box, which runs `mix phx.server` in `:dev`. So setting the env below
makes real email send regardless of dev/prod mode.

- **test:** always the in-memory Test adapter (no send).
- **otherwise (dev, prod, the deployed box):** safe by default — with nothing
  configured it uses the local preview adapter (nothing sent), so an
  unconfigured deploy never crashes. Set `RESEND_API_KEY` (below) to send real
  mail.

**Recommended: Resend.** Set `RESEND_API_KEY` and it is used automatically (it
takes precedence over SMTP). Setup:

1. Create an API key in the Resend dashboard (it starts with `re_`).
2. Verify your sending domain in Resend (the `MAILER_FROM` address must be on a
   verified domain). For a quick test you can send from `onboarding@resend.dev`
   — but that sandbox sender only delivers to your own Resend account email.
3. Set in `/opt/andnativeai/.env`:

   ```sh
   RESEND_API_KEY=re_...
   MAILER_FROM=no-reply@andnativeai.marcelfahle.net   # a Resend-verified sender
   ```

**Both are required:** `RESEND_API_KEY` authenticates, and `MAILER_FROM` must be
a verified Resend sender — sends from an unverified domain are rejected. No
`MAILER_ADAPTER` is needed; because the server now runs in `MIX_ENV=prod`, the
next deploy delivers via Resend through the prod runtime config.

**Alternative: SMTP.** Instead of Resend, set `MAILER_ADAPTER=smtp` plus the
`SMTP_*` vars:

```sh
MAILER_ADAPTER=smtp
SMTP_RELAY=smtp.your-provider.com
SMTP_USERNAME=...
SMTP_PASSWORD=...
SMTP_PORT=587
MAILER_FROM=no-reply@andnativeai.marcelfahle.net   # optional; defaults to no-reply@<host>
```

No secret is committed; `RESEND_API_KEY` and the SMTP credentials all come from
the environment.

### Local setup

```sh
mix setup        # deps, DB create + migrate (seeds the first admin), assets
mix phx.server   # http://localhost:4000/login  ->  m.fahle@gmail.com / changeme123
```

## Verify

```sh
docker compose -p andnativeai -f /opt/andnativeai/deploy/hetzner-demo.compose.yml ps
curl -I https://andnativeai.marcelfahle.net/admin/agents
```

Expected:

- With Caddy basic auth removed: an unauthenticated request to `/admin/agents`
  returns `302` to `/login`; after logging in, the admin UI loads.
- With Caddy basic auth kept as an outer belt: the request returns `401` at the
  Caddy layer first, with the app login behind it.

## Slack OAuth

The server still needs `SLACK_APP_TOKEN` in `/opt/andnativeai/.env` so Socket
Mode can open the app-level WebSocket.

Workspace OAuth onboarding can be completed from the UI:

1. Open `https://andnativeai.marcelfahle.net/admin/slack`.
2. Save the Slack app Client ID, Client Secret, Redirect URI, and bot scopes in
   **OAuth app settings**.
3. Add the same redirect URI in Slack's **OAuth & Permissions** settings:
   `https://andnativeai.marcelfahle.net/slack/oauth/callback`.
4. Click **Connect Slack** and approve the app.

PoC caveat: saved Slack OAuth app settings are plaintext in Postgres.

## Backups

Snapshot or back up:

- `/opt/andnativeai/var/postgres`
- `/opt/andnativeai/var/sources`
- `/opt/andnativeai/var/openclaw`
