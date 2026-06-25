#!/usr/bin/env bash
set -euo pipefail
kubectl delete namespace customer-portal --ignore-not-found
echo "Done - ELB deprovisioned."
