#!/bin/sh
set -eu

if [ ! -f .env ]; then
  cp .env.example .env
fi

docker compose up -d postgres redis minio control-panel
docker compose exec -T control-panel mix run scripts/compose_persistence_probe.exs seed
docker compose restart postgres control-panel
sleep 12
docker compose exec -T control-panel mix run scripts/compose_persistence_probe.exs assert
