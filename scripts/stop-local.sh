#!/usr/bin/env bash
# Remove the local demo containers and network.
set -euo pipefail
docker rm -f portal postgres >/dev/null 2>&1 || true
docker network rm customer-portal >/dev/null 2>&1 || true
echo "Stopped and cleaned up."
