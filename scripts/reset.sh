#!/usr/bin/env bash
set -euo pipefail
kubectl delete namespace golden-demo --ignore-not-found
echo "Done - ELB deprovisioned."
