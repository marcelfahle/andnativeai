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
ADMIN_PASSWORD="$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-20)"

# sed is avoided on purpose: generated secrets can contain any delimiter.
TEMPLATE="$REPO_DIR/deploy/appliance.env.template"
python3 - "$TEMPLATE" "$BASE/.env" <<PYEOF
import sys
template_path, out_path = sys.argv[1], sys.argv[2]
replacements = {
    "__DOMAIN__": """$DOMAIN""",
    "__SECRET_KEY_BASE__": """$SECRET_KEY_BASE""",
    "__POSTGRES_PASSWORD__": """$POSTGRES_PASSWORD""",
    "__MINIO_ROOT_PASSWORD__": """$MINIO_ROOT_PASSWORD""",
    "__CLOAK_KEY__": """$CLOAK_KEY""",
    "__ADMIN_EMAIL__": """$ADMIN_EMAIL""",
    "__ADMIN_PASSWORD__": """$ADMIN_PASSWORD""",
    "__REPO_DIR__": """$REPO_DIR""",
    "__CADDY_NETWORK__": """$CADDY_NETWORK""",
}
content = open(template_path).read()
for marker, value in replacements.items():
    content = content.replace(marker, value)
open(out_path, "w").write(content)
PYEOF
chmod 600 "$BASE/.env"

cp "$REPO_DIR/deploy/appliance.compose.yml" "$BASE/compose.yml"

echo "==> Building and starting Compose project $PROJECT"
"${COMPOSE[@]}" up -d --build

echo "==> Waiting for the control plane to become healthy (migrations run on boot)"
for _attempt in $(seq 1 60); do
  status="$("${COMPOSE[@]}" ps --format '{{.Service}} {{.Health}}' 2>/dev/null |
    awk '$1 == "control-panel" { print $2 }')"
  [ "$status" = "healthy" ] && break
  sleep 5
done

if [ "${status:-}" != "healthy" ]; then
  echo "error: control-panel did not become healthy; inspect with:" >&2
  echo "       ${COMPOSE[*]} logs control-panel" >&2
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

cat <<SUMMARY

Appliance '$SLUG' is up.

  URL            https://$DOMAIN  (once the Caddy vhost is live)
  Admin login    $ADMIN_EMAIL
  Admin password $ADMIN_PASSWORD   <- stored in $BASE/.env; rotate after first login
  Compose        ${COMPOSE[*]}

Go-live checklist:
  1. DNS: point $DOMAIN at this VM.
  2. Caddy: add $BASE/caddy.vhost to the Caddy config (it reaches the
     appliance over the '$CADDY_NETWORK' network) and reload Caddy.
  3. Providers: set OPENAI_API_KEY (and research keys) in $BASE/.env,
     then: ${COMPOSE[*]} up -d
  4. Slack: create the customer's Slack app, fill SLACK_* in $BASE/.env,
     connect via https://$DOMAIN/admin/slack.
  5. Superadmin (platform staff only):
     ${COMPOSE[*]} exec control-panel ./bin/andnative_ai eval 'AndnativeAi.Release.promote_superadmin("you@andnative.ai")'
SUMMARY
