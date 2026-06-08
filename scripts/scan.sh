#!/usr/bin/env bash
# Scan the portal image with sysdig-cli-scanner against the on-prem backend.
# Usage: SYSDIG_SECURE_URL=https://... SECURE_API_TOKEN=... ./scan.sh
set -euo pipefail

: "${SYSDIG_SECURE_URL:?set SYSDIG_SECURE_URL}"
: "${SECURE_API_TOKEN:?set SECURE_API_TOKEN}"
IMAGE="${IMAGE:-}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ -z "$IMAGE" ]; then
  ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null \
    || aws sts get-caller-identity --profile draios-dev --query Account --output text)
  REGION=$(aws configure get region 2>/dev/null || echo "ap-southeast-2")
  IMAGE="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com/golden-demo/portal:vuln"
fi

BIN="$ROOT/sysdig-cli-scanner"
if [ ! -x "$BIN" ]; then
  OS=$(uname -s | tr '[:upper:]' '[:lower:]')
  ARCH=$(uname -m); [ "$ARCH" = "x86_64" ] && ARCH=amd64
  VERSION=$(curl -sL https://download.sysdig.com/scanning/sysdig-cli-scanner/latest_version.txt)
  echo "Downloading sysdig-cli-scanner ${VERSION}..."
  curl -sL -o "$BIN" \
    "https://download.sysdig.com/scanning/bin/sysdig-cli-scanner/${VERSION}/${OS}/${ARCH}/sysdig-cli-scanner"
  chmod +x "$BIN"
fi

SECURE_API_TOKEN="$SECURE_API_TOKEN" "$BIN" \
  --apiurl "$SYSDIG_SECURE_URL" \
  --api-skiptlsverify \
  "docker://${IMAGE}"
