#!/usr/bin/env bash
# Build and start the portal + Postgres on a shared Docker network.
set -euo pipefail

NET=customer-portal
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

docker network inspect "$NET" >/dev/null 2>&1 || docker network create "$NET"
docker rm -f portal postgres >/dev/null 2>&1 || true

docker run -d --name postgres --network "$NET" \
  -e POSTGRES_USER=portal -e POSTGRES_PASSWORD=s3cr3t -e POSTGRES_DB=customers \
  -v "$ROOT/db/initdb:/docker-entrypoint-initdb.d:ro" \
  postgres:13

docker build -t customer-portal/portal:2.5.10 "$ROOT/app"

# PGPASSWORD is deliberately in the portal env - it is exactly what the attacker
# steals. Mirrors the Kubernetes Secret-to-env pattern Plan 2 uses.
docker run -d --name portal --network "$NET" \
  -e PGHOST=postgres -e PGDATABASE=customers -e PGUSER=portal -e DB_PASSWORD=s3cr3t \
  -p 8080:8080 \
  customer-portal/portal:2.5.10

echo "Started. Give Tomcat ~20s to deploy the WAR."
