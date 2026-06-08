#!/usr/bin/env bash
# Scan the portal image with sysdig-cli-scanner against the on-prem backend.
# Usage: ./scan.sh <sysdig-secure-url> <api-token> [image]
# Example: ./scan.sh https://sysdig.example.com mytoken123
set -euo pipefail

SYSDIG_SECURE_URL="${1:?Usage: scan.sh <sysdig-url> <api-token> [image]}"
SECURE_API_TOKEN="${2:?Usage: scan.sh <sysdig-url> <api-token> [image]}"
IMAGE="${3:-}"

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
