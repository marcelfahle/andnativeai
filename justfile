# &native.ai — common commands. Run `just` to list.

set dotenv-load := true

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

# --- Deploy ---

# Deploy to Hetzner (push to main triggers CI in .github/workflows/deploy-main.yml)
deploy:
    git push origin main

# Tail production logs on the Hetzner host
prod-logs:
    ssh andnative-deploy@91.99.49.152 'cd /opt/andnativeai/deploy && docker compose -p andnativeai -f hetzner-demo.compose.yml logs -f --tail=100'

# Show production container status
prod-ps:
    ssh andnative-deploy@91.99.49.152 'cd /opt/andnativeai/deploy && docker compose -p andnativeai -f hetzner-demo.compose.yml ps'
