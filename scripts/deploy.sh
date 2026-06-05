#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NS=golden-demo

kubectl apply -f "$ROOT/k8s/00-namespace.yaml"
kubectl create configmap pg-initdb --from-file="$ROOT/db/initdb/seed.sql" \
  -n "$NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "$ROOT/k8s/10-postgres.yaml"
kubectl apply -f "$ROOT/k8s/20-portal.yaml"

kubectl rollout status deploy/postgres -n "$NS" --timeout=120s
kubectl rollout status deploy/portal -n "$NS" --timeout=180s

echo "Waiting for LoadBalancer..."
LB=""
for _ in $(seq 1 30); do
  LB=$(kubectl get svc portal -n "$NS" \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  [ -n "$LB" ] && break
  sleep 10
done

[ -z "$LB" ] && echo "LB not ready - check: kubectl get svc portal -n $NS" && exit 1
echo "http://${LB}/"
