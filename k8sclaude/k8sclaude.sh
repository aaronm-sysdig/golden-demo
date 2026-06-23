#!/usr/bin/env bash
# k8sclaude.sh - deploy a Claude Code pod to sysdn03 and exec in
set -euo pipefail

CONTEXT="arn:aws:eks:ap-southeast-2:059797578166:cluster/cni-test-cluster"
NAMESPACE="claude"
POD="claude-demo"
CREDS_FILE="$HOME/.claude/.credentials.json"
DIR="$(cd "$(dirname "$0")" && pwd)"

K="kubectl --context=$CONTEXT"

usage() {
  echo "Usage: $0 [--cleanup]"
  echo "  --cleanup   delete the pod and secret after use"
  exit 1
}

cleanup() {
  echo "==> Cleaning up..."
  $K delete pod "$POD" -n "$NAMESPACE" --ignore-not-found
  $K delete secret claude-credentials -n "$NAMESPACE" --ignore-not-found
}

if [[ "${1:-}" == "--cleanup" ]]; then
  cleanup
  exit 0
elif [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
  usage
fi

# -- namespace --
echo "==> Namespace: $NAMESPACE"
$K apply -f "$DIR/k8s/00-namespace.yaml"

# -- credentials (optional - skip if not present, login inside pod instead) --
if [[ -f "$CREDS_FILE" ]]; then
  echo "==> Syncing credentials secret from $CREDS_FILE ..."
  $K delete secret claude-credentials -n "$NAMESPACE" --ignore-not-found >/dev/null
  $K create secret generic claude-credentials \
    --from-file=credentials.json="$CREDS_FILE" \
    -n "$NAMESPACE"
  CREDS_AVAILABLE=true
else
  echo "==> No local credentials found - you'll need to run 'claude login' inside the pod."
  echo "    After logging in, run: kubectl --context=$CONTEXT exec $POD -n $NAMESPACE -- cat /root/.claude/.credentials.json > $CREDS_FILE"
  echo "    Then re-run this script to have credentials auto-injected on future runs."
  echo ""
  $K delete secret claude-credentials -n "$NAMESPACE" --ignore-not-found >/dev/null 2>&1 || true
  CREDS_AVAILABLE=false
fi

# -- pod --
echo "==> Applying pod manifest..."
$K delete pod "$POD" -n "$NAMESPACE" --ignore-not-found --grace-period=0 --force >/dev/null 2>&1 || true
if [[ "$CREDS_AVAILABLE" == "true" ]]; then
  $K apply -f "$DIR/k8s/10-pod.yaml"
else
  # Run pod without credentials volume mount
  $K apply -f "$DIR/k8s/10-pod-nocreds.yaml"
fi

echo "==> Waiting for pod to be ready..."
$K wait pod "$POD" -n "$NAMESPACE" \
  --for=condition=Ready \
  --timeout=120s

echo ""
if [[ "$CREDS_AVAILABLE" == "true" ]]; then
  echo "==> Starting demo..."
  echo "    Run '$0 --cleanup' when done."
  echo ""
  $K exec -t "$POD" -n "$NAMESPACE" -- trigger-ai-rules
else
  echo "==> Execing into pod shell - run 'claude login' to authenticate."
  echo "    Then from a second terminal extract credentials:"
  echo "    $K exec $POD -n $NAMESPACE -- cat /root/.claude/.credentials.json > $CREDS_FILE"
  echo "    Then re-run this script."
  echo ""
  $K exec -it "$POD" -n "$NAMESPACE" -- /bin/bash
fi
