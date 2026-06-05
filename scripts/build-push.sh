#!/usr/bin/env bash
# Build the portal for linux/amd64 and push to ECR in the cluster's account.
set -euo pipefail

export AWS_PROFILE=draios-dev
ACCOUNT=059797578166
REGION=ap-southeast-2
REPO=golden-demo/portal
TAG=vuln
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REGISTRY="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"
IMAGE="${REGISTRY}/${REPO}:${TAG}"

aws ecr describe-repositories --region "$REGION" --repository-names "$REPO" >/dev/null 2>&1 \
  || aws ecr create-repository --region "$REGION" --repository-name "$REPO" >/dev/null

aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"

# EKS nodes are amd64; the build host (colima) is arm64, so set the platform.
docker build --platform linux/amd64 -t "$IMAGE" "$ROOT/app"
docker push "$IMAGE"
echo "Pushed $IMAGE"
