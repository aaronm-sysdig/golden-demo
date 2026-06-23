#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NS=golden-demo

kubectl apply -f "$ROOT/k8s/00-namespace.yaml"
kubectl create configmap pg-initdb --from-file="$ROOT/db/initdb/seed.sql" \
  -n "$NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "$ROOT/k8s/10-postgres.yaml"
kubectl apply -f "$ROOT/k8s/20-portal.yaml"
kubectl apply -f "$ROOT/k8s/30-portal-networkpolicy.yaml"

kubectl rollout status deploy/postgres -n "$NS" --timeout=120s
kubectl rollout status deploy/portal -n "$NS" --timeout=180s

echo ""
echo "Deployed (ClusterIP, not internet-exposed). Sysdig sees the image + runtime."
echo "To drive the exploit, just run:  ./scripts/exploit.sh"
echo "(it sets up its own port-forward; or manually:"
echo "  kubectl port-forward -n $NS svc/portal 8080:80 )"
