#!/usr/bin/env bash
# Tear down the AI workload between demos. Removes the namespace (deployment,
# service, secret, network policy all go with it). Nothing here is internet
# exposed, but tearing it down shrinks the window an intentionally-vulnerable
# workload is live on the cluster.
set -euo pipefail
kubectl delete namespace ai-workload --ignore-not-found
echo "Done - ai-workload namespace removed."
