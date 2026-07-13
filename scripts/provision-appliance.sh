#!/usr/bin/env bash
#
# Fire up a new &native.ai appliance on this VM in one command.
#
#   scripts/provision-appliance.sh <slug> <domain> <admin-email>
#
#   scripts/provision-appliance.sh acme acme.andnative.ai founder@acme.example
#
# What it does (each step maps 1:1 to a future Helm value — see
# docs/plans/2026-07-11-001-appliance-provisioning-and-super-admin.md):
#   1. renders /opt/appliances/<slug>/.env from deploy/appliance.env.template
#      with freshly generated SECRET_KEY_BASE, POSTGRES_PASSWORD,
#      MINIO_ROOT_PASSWORD, CLOAK_KEY, and a first-admin password
#   2. copies the generic Compose project (deploy/appliance.compose.yml)
#      and creates the per-appliance volume directories
#   3. builds and starts the appliance under its own Compose project name
#      (one VM hosts several appliances side by side)
#   4. waits for the control plane to become healthy (migrations run on
#      boot) and seeds the first admin
#   5. writes the Caddy vhost snippet and prints the go-live checklist
#
# Environment overrides:
#   APPLIANCES_ROOT  base directory for appliances   (default /opt/appliances)
#   CADDY_NETWORK    external Docker network Caddy is on (default deploy_default)

set -euo pipefail

usage() {
  echo "usage: $0 <slug> <domain> <admin-email>" >&2
  exit 64
}

[ $# -eq 3 ] || usage
SLUG="$1"
DOMAIN="$2"
ADMIN_EMAIL="$3"

case "$DOMAIN" in
  *[!a-z0-9.-]* | "" | .* | *. | *..* )
    echo "error: domain must be a bare lowercase hostname (got '$DOMAIN')" >&2
    exit 64
    ;;
  *.*) ;;
  *)
    echo "error: domain needs at least one dot (got '$DOMAIN')" >&2
    exit 64
    ;;
esac

case "$SLUG" in
  *[!a-z0-9-]* | "" | -* )
    echo "error: slug must be lowercase letters, digits, and dashes (got '$SLUG')" >&2
    exit 64
    ;;
esac

case "$ADMIN_EMAIL" in
  *@*) ;;
  *)
    echo "error: '$ADMIN_EMAIL' does not look like an email address" >&2
    exit 64
    ;;
esac

# Platform staff seeded as superadmins in every appliance (AAI-34).
PLATFORM1_EMAIL="${PLATFORM1_EMAIL:-m.fahle@gmail.com}"
PLATFORM2_EMAIL="${PLATFORM2_EMAIL:-matthewosullivan87@gmail.com}"

# A customer admin email colliding with a platform email would make the
# two seed slots fight over one row. users.email is citext, so compare
# case-insensitively — "M.Fahle@gmail.com" must still be caught.
admin_email_lc="$(printf '%s' "$ADMIN_EMAIL" | tr '[:upper:]' '[:lower:]')"
for platform_email in "$PLATFORM1_EMAIL" "$PLATFORM2_EMAIL"; do
  platform_email_lc="$(printf '%s' "$platform_email" | tr '[:upper:]' '[:lower:]')"
  if [ "$admin_email_lc" = "$platform_email_lc" ]; then
    echo "error: admin email '$ADMIN_EMAIL' is a platform staff address" >&2
    exit 64
  fi
done

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APPLIANCES_ROOT="${APPLIANCES_ROOT:-/opt/appliances}"
CADDY_NETWORK="${CADDY_NETWORK:-deploy_default}"
BASE="$APPLIANCES_ROOT/$SLUG"
PROJECT="andnative-$SLUG"
COMPOSE=(docker compose -p "$PROJECT" --env-file "$BASE/.env" -f "$BASE/compose.yml")

if [ -e "$BASE/.env" ]; then
  echo "error: $BASE/.env already exists — appliance '$SLUG' looks provisioned." >&2
  echo "       To reprovision, retire it first (compose down + move the directory away)." >&2
  exit 1
fi

echo "==> Creating appliance directory $BASE"
mkdir -p "$BASE"/var/postgres "$BASE"/var/redis "$BASE"/var/minio \
  "$BASE"/var/sources "$BASE"/var/openclaw

echo "==> Generating secrets and rendering .env"
SECRET_KEY_BASE="$(openssl rand -base64 48 | tr -d '\n')"
POSTGRES_PASSWORD="$(openssl rand -hex 24)"
MINIO_ROOT_PASSWORD="$(openssl rand -hex 24)"
CLOAK_KEY="$(openssl rand -base64 32)"
MEMORY_TOOL_TOKEN="$(openssl rand -hex 24)"
# hex: fixed length, always clears the 12-char minimum password validation.
ADMIN_PASSWORD="$(openssl rand -hex 10)"
PLATFORM1_PASSWORD="$(openssl rand -hex 10)"
PLATFORM2_PASSWORD="$(openssl rand -hex 10)"

# Values reach python through the environment (never interpolated into
# code — secrets and user input cannot break or inject the renderer), and
# the file is created 0600 before any secret is written.
TEMPLATE="$REPO_DIR/deploy/appliance.env.template"
env TPL_DOMAIN="$DOMAIN" \
  TPL_SECRET_KEY_BASE="$SECRET_KEY_BASE" \
  TPL_POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
  TPL_MINIO_ROOT_PASSWORD="$MINIO_ROOT_PASSWORD" \
  TPL_CLOAK_KEY="$CLOAK_KEY" \
  TPL_MEMORY_TOOL_TOKEN="$MEMORY_TOOL_TOKEN" \
  TPL_ADMIN_EMAIL="$ADMIN_EMAIL" \
  TPL_ADMIN_PASSWORD="$ADMIN_PASSWORD" \
  TPL_PLATFORM1_EMAIL="$PLATFORM1_EMAIL" \
  TPL_PLATFORM1_PASSWORD="$PLATFORM1_PASSWORD" \
  TPL_PLATFORM2_EMAIL="$PLATFORM2_EMAIL" \
  TPL_PLATFORM2_PASSWORD="$PLATFORM2_PASSWORD" \
  TPL_REPO_DIR="$REPO_DIR" \
  TPL_CADDY_NETWORK="$CADDY_NETWORK" \
  python3 - "$TEMPLATE" "$BASE/.env" <<'PYEOF'
import os
import sys

template_path, out_path = sys.argv[1], sys.argv[2]
markers = [
    "DOMAIN",
    "SECRET_KEY_BASE",
    "POSTGRES_PASSWORD",
    "MINIO_ROOT_PASSWORD",
    "CLOAK_KEY",
    "MEMORY_TOOL_TOKEN",
    "ADMIN_EMAIL",
    "ADMIN_PASSWORD",
    "PLATFORM1_EMAIL",
    "PLATFORM1_PASSWORD",
    "PLATFORM2_EMAIL",
    "PLATFORM2_PASSWORD",
    "REPO_DIR",
    "CADDY_NETWORK",
]
content = open(template_path).read()
for marker in markers:
    content = content.replace(f"__{marker}__", os.environ[f"TPL_{marker}"])

fd = os.open(out_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, "w") as out:
    out.write(content)
PYEOF

cp "$REPO_DIR/deploy/appliance.compose.yml" "$BASE/compose.yml"

echo "==> Building and starting Compose project $PROJECT"
"${COMPOSE[@]}" up -d --build

echo "==> Waiting for the control plane to become healthy (migrations run on boot)"
# docker inspect on the container id is stable across compose versions,
# and every probe tolerates transient failures instead of tripping set -e.
for _attempt in $(seq 1 60); do
  container_id="$("${COMPOSE[@]}" ps -q control-panel 2>/dev/null || true)"

  if [ -n "$container_id" ]; then
    status="$(docker inspect --format '{{.State.Health.Status}}' "$container_id" 2>/dev/null || true)"
    [ "$status" = "healthy" ] && break
  fi

  sleep 5
done

if [ "${status:-}" != "healthy" ]; then
  echo "error: control-panel did not become healthy; inspect with:" >&2
  echo "       ${COMPOSE[*]} logs control-panel" >&2
  echo "" >&2
  echo "To retry from scratch (the already-provisioned guard will otherwise refuse):" >&2
  echo "       ${COMPOSE[*]} down" >&2
  echo "       mv '$BASE' '$BASE.failed.$(date +%s)'" >&2
  exit 1
fi

echo "==> Seeding the first admin ($ADMIN_EMAIL)"
"${COMPOSE[@]}" exec -T control-panel ./bin/andnative_ai eval "AndnativeAi.Release.seed()"

echo "==> Writing Caddy vhost snippet"
cat > "$BASE/caddy.vhost" <<CADDYEOF
$DOMAIN {
    reverse_proxy $PROJECT-control-panel-1:4000
}
CADDYEOF

if [ "${QUIET_CREDENTIALS:-false}" = "true" ]; then
  credentials_line="stored in $BASE/.env (QUIET_CREDENTIALS — read them over SSH)"
else
  credentials_line="$ADMIN_PASSWORD   <- stored in $BASE/.env; rotate after first login"
fi

cat <<SUMMARY

Appliance '$SLUG' is up.

  URL            https://$DOMAIN  (once the Caddy vhost is live)
  Admin login    $ADMIN_EMAIL
  Admin password $credentials_line
  Compose        ${COMPOSE[*]}

Go-live checklist:
  1. DNS: point $DOMAIN at this VM.
  2. Caddy: add $BASE/caddy.vhost to the Caddy config (it reaches the
     appliance over the '$CADDY_NETWORK' network) and reload Caddy.
  3. Providers: set OPENAI_API_KEY (and ANTHROPIC_API_KEY / research keys) in $BASE/.env,
     then: ${COMPOSE[*]} up -d
  4. Slack: create the customer's Slack app, fill SLACK_* in $BASE/.env,
     connect via https://$DOMAIN/admin/slack.
  5. Superadmin (platform staff only):
     ${COMPOSE[*]} exec control-panel ./bin/andnative_ai eval 'AndnativeAi.Release.promote_superadmin("you@andnative.ai")'
SUMMARY
