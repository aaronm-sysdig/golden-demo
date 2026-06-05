#!/usr/bin/env bash
# Deploy the golden demo to EKS and print the LoadBalancer URL.
set -euo pipefail

export AWS_PROFILE=draios-dev
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NS=golden-demo

kubectl apply -f "$ROOT/k8s/00-namespace.yaml"

# ConfigMap from the single source of truth (db/initdb/seed.sql).
kubectl create configmap pg-initdb \
  --from-file="$ROOT/db/initdb/seed.sql" \
  -n "$NS" --dry-run=client -o yaml | kubectl apply -f -

# Apply Postgres and the portal. Admission-controller warnings (if the Sysdig
# policy is in warn mode) print here but do not stop the apply.
kubectl apply -f "$ROOT/k8s/10-postgres.yaml"
kubectl apply -f "$ROOT/k8s/20-portal.yaml"

echo "Waiting for rollouts..."
kubectl rollout status deploy/postgres -n "$NS" --timeout=120s
kubectl rollout status deploy/portal -n "$NS" --timeout=180s

echo "Waiting for the LoadBalancer hostname..."
LB=""
for _ in $(seq 1 30); do
  LB=$(kubectl get svc portal -n "$NS" \
        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  [ -n "$LB" ] && break
  sleep 10
done

if [ -z "$LB" ]; then
  echo "LoadBalancer hostname not assigned yet. Check: kubectl get svc portal -n $NS"
  exit 1
fi

echo "Portal LoadBalancer: http://${LB}/"
echo "Note: the ELB DNS can take 2-3 minutes to resolve after first assignment."
