#!/usr/bin/env bash
# Tear down the demo (also deprovisions the ELB created by the LoadBalancer svc).
set -euo pipefail
export AWS_PROFILE=draios-dev
kubectl delete namespace golden-demo --ignore-not-found
echo "Deleted golden-demo namespace. The ELB deprovisions automatically."
