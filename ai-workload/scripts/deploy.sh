#!/usr/bin/env bash
# Deploys the langchain AI workload to the ai-workload namespace on the current
# kube context (EKS cni-test-cluster / sysdn03 in Sysdig).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NS=ai-workload

kubectl apply -f "$ROOT/k8s/00-namespace.yaml"
kubectl apply -f "$ROOT/k8s/10-ai-workload.yaml"
kubectl apply -f "$ROOT/k8s/20-networkpolicy.yaml"

kubectl rollout status deploy/langchain-ai -n "$NS" --timeout=180s

echo ""
echo "Deployed (ClusterIP, not internet-exposed). Sysdig sees the image + runtime."
echo "To drive the exploit, just run:  ./scripts/exploit.sh"
echo "(it sets up its own port-forward; or manually:"
echo "  kubectl port-forward -n $NS svc/langchain-ai 8088:80 )"
