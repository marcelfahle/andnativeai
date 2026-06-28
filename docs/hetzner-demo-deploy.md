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
- Caddy terminates TLS and protects the admin UI with basic auth

The importer already owns host port `4000`, so this PoC must not publish host
port `4000`.

## Deploy Or Update

From local repo:

```sh
rsync -az --delete \
  --exclude .git \
  --exclude .DS_Store \
  --exclude _build \
  --exclude deps \
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

Add a vhost:

```caddyfile
andnativeai.marcelfahle.net {
  encode zstd gzip
  basic_auth {
    marcel <hashed-password>
    matt <hashed-password>
  }
  reverse_proxy andnative-control-panel:4000
}
```

Reload Caddy:

```sh
docker exec bold-mcp-caddy caddy reload --config /etc/caddy/Caddyfile
```

## Verify

```sh
docker compose -p andnativeai -f /opt/andnativeai/deploy/hetzner-demo.compose.yml ps
curl -I https://andnativeai.marcelfahle.net
```

Expected:

- unauthenticated HTTPS returns `401`
- authenticated browser access reaches `/admin/agents`

## Backups

Snapshot or back up:

- `/opt/andnativeai/var/postgres`
- `/opt/andnativeai/var/sources`
- `/opt/andnativeai/var/openclaw`
