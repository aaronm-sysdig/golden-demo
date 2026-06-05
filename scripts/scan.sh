#!/usr/bin/env bash
# Scan the portal image with sysdig-cli-scanner against the on-prem backend.
# Inputs (env):
#   SYSDIG_SECURE_URL  - on-prem Sysdig Secure base URL (no trailing /secure)
#   SECURE_API_TOKEN   - Sysdig Secure API token (falls back to ./.sysdig-token)
set -euo pipefail

: "${SYSDIG_SECURE_URL:?set SYSDIG_SECURE_URL to the on-prem Sysdig Secure base URL}"
if [ -z "${SECURE_API_TOKEN:-}" ] && [ -f .sysdig-token ]; then
  SECURE_API_TOKEN="$(cat .sysdig-token)"
fi
: "${SECURE_API_TOKEN:?set SECURE_API_TOKEN (or create ./.sysdig-token)}"

ACCOUNT=059797578166
REGION=ap-southeast-2
IMAGE="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com/golden-demo/portal:vuln"

OS=$(uname -s | tr '[:upper:]' '[:lower:]')   # darwin / linux
ARCH=$(uname -m)                               # arm64 / x86_64
[ "$ARCH" = "x86_64" ] && ARCH=amd64

BIN=./sysdig-cli-scanner
if [ ! -x "$BIN" ]; then
  VERSION=$(curl -sL https://download.sysdig.com/scanning/sysdig-cli-scanner/latest_version.txt)
  echo "Downloading sysdig-cli-scanner ${VERSION} (${OS}/${ARCH})..."
  curl -sL -o "$BIN" \
    "https://download.sysdig.com/scanning/bin/sysdig-cli-scanner/${VERSION}/${OS}/${ARCH}/sysdig-cli-scanner"
  chmod +x "$BIN"
fi

# The portal image is already built locally (tagged as the ECR URI), so scan the
# local docker image to avoid a registry pull.
SECURE_API_TOKEN="$SECURE_API_TOKEN" "$BIN" \
  --apiurl "$SYSDIG_SECURE_URL" \
  --storagetype docker \
  "docker://${IMAGE}"
