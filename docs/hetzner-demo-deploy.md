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
4. Run the existing Compose deploy command.
5. Force-recreate `control-panel` and `slack-listener` so the running BEAM
   processes pick up the synced code.
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
docker compose -p andnativeai -f hetzner-demo.compose.yml up -d --build
```

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

The `control-panel` entrypoint (`bin/control-panel`) already runs
`mix ecto.migrate` and `mix run priv/repo/seeds.exs` on every start, so the
`users` table is created and admins are (re)seeded automatically on deploy.

### Seeding the initial admins

Marcel (`m.fahle@gmail.com`) is always the first user. Passwords are read from
the environment — **no password is ever stored in the repo or in this doc.**
Add them to `/opt/andnativeai/.env`:

```sh
SEED_MARCEL_PASSWORD=...
SEED_MATT_PASSWORD=...
SEED_MATT_EMAIL=matt@...
```

On the next deploy (or `docker compose ... up -d`), the entrypoint seeds the
admins. Seeding is idempotent: an existing user is left untouched (its password
is **not** reset), and a user whose `SEED_*_PASSWORD` is unset is skipped with a
notice. To seed without a full restart, run the seeds in the running container:

```sh
docker compose -p andnativeai -f /opt/andnativeai/deploy/hetzner-demo.compose.yml \
  exec control-panel mix run priv/repo/seeds.exs
```

### Rotating or adding users

- **Rotate a password:** delete the user, then re-run the seeds with the new
  `SEED_*_PASSWORD` set:

  ```sh
  docker compose -p andnativeai -f /opt/andnativeai/deploy/hetzner-demo.compose.yml \
    exec control-panel \
    mix run -e 'AndnativeAi.Accounts.get_user_by_email("user@example.com") |> AndnativeAi.Repo.delete!()'
  ```

- **Add a user:** run
  `mix run -e 'AndnativeAi.Accounts.register_user(%{email: "...", password: "..."})'`
  in the container, or set another `SEED_*` pair and re-run the seeds.

### Local setup

```sh
mix setup                                              # deps, DB create + migrate + seed, assets
SEED_MARCEL_PASSWORD=... mix run priv/repo/seeds.exs   # seed an admin to log in with
mix phx.server                                         # http://localhost:4000/login
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
