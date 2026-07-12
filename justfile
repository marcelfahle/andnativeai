# &native.ai — common commands. Run `just` to list.

set dotenv-load := true

# Production appliance coordinates. Override per invocation when more
# appliances exist: `just prod_host=deploy@other-box prod-ps`
prod_host := "andnative-deploy@91.99.49.152"
prod_dir := "/opt/andnativeai"
prod_compose := "docker compose -p andnativeai -f hetzner-demo.compose.yml"
prod_url := "https://andnativeai.marcelfahle.net"

# Show available recipes
default:
    @just --list

# `just dev` is an alias for `just up`
alias dev := up

# --- Local dev (Docker) ---

# First run: build images and start the full stack (app on :4000)
up:
    docker compose up --build

# Start the stack in the background
upd:
    docker compose up --build -d

# Stop the stack
down:
    docker compose down

# Tail logs (optionally a service: `just logs control-panel`)
logs service="":
    docker compose logs -f {{service}}

# --- Local dev (no Docker) ---

# Install deps + db + assets (one-time setup)
setup:
    mix setup

# Run the Phoenix server (http://localhost:4000)
server:
    mix phx.server

# Run the server with an IEx shell attached
iex:
    iex -S mix phx.server

# --- Database ---

# Create db and run migrations
migrate:
    mix ecto.migrate

# Roll back the last migration (`just rollback 3` for more)
rollback n="1":
    mix ecto.rollback -n {{n}}

# Drop, recreate, migrate and seed
reset:
    mix ecto.reset

# Run seeds
seed:
    mix run priv/repo/seeds.exs

# --- Quality ---

# Format, lint, compile with warnings as errors, and test
check:
    mix precommit

# Run the test suite
test:
    mix test

# --- Demo (local Compose stack) ---

# Clear demo memory sources/items; keeps agents, config, and audit evidence
demo-reset:
    docker compose exec -T control-panel mix run scripts/reset-demo-memory.exs

# Re-ingest one Slack channel from current history: `just demo-backfill C0123456789`
demo-backfill channel:
    docker compose exec -T control-panel mix run scripts/backfill-slack-channel.exs {{channel}}

# Verify memory survives a Compose restart
demo-persistence:
    scripts/compose-persistence-check.sh

# --- Demo (live Hetzner appliance) ---

# Clear demo memory on the live appliance (release-safe; keeps agents + audit evidence)
prod-demo-reset:
    ssh {{prod_host}} 'cd {{prod_dir}}/deploy && {{prod_compose}} exec -T control-panel ./bin/andnative_ai eval "AndnativeAi.Release.reset_demo_memory()"'

# Re-ingest one Slack channel on the live appliance: `just prod-demo-backfill C0123456789`
prod-demo-backfill channel:
    ssh {{prod_host}} 'cd {{prod_dir}}/deploy && {{prod_compose}} exec -T control-panel ./bin/andnative_ai eval "AndnativeAi.Release.backfill_slack_channel(\"{{channel}}\")"'

# Restart the live app containers (persistence demo; data must survive)
prod-restart:
    ssh {{prod_host}} 'cd {{prod_dir}}/deploy && {{prod_compose}} restart control-panel slack-listener'

# Run an arbitrary release expression on the live appliance: `just prod-eval "AndnativeAi.Release.migrate()"`
prod-eval expr:
    ssh {{prod_host}} 'cd {{prod_dir}}/deploy && {{prod_compose}} exec -T control-panel ./bin/andnative_ai eval "{{expr}}"'

# --- Deploy & production ---

# Deploy to Hetzner (push to main triggers CI in .github/workflows/deploy-main.yml)
deploy:
    git push origin main

# Watch the latest Deploy Main run until it finishes
deploy-watch:
    gh run watch $(gh run list --branch main --limit 1 --json databaseId --jq '.[0].databaseId') --exit-status

# Tail production logs on the Hetzner host
prod-logs:
    ssh {{prod_host}} 'cd {{prod_dir}}/deploy && {{prod_compose}} logs -f --tail=100'

# Show production container status
prod-ps:
    ssh {{prod_host}} 'cd {{prod_dir}}/deploy && {{prod_compose}} ps'

# Open a shell on the Hetzner host
prod-ssh:
    ssh -t {{prod_host}} 'cd {{prod_dir}}; exec $SHELL -l'

# Open the live admin UI
prod-open:
    open {{prod_url}}/admin/control-plane
