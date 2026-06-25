#!/usr/bin/env bash
# Builds the portal image for linux/amd64 and pushes to ECR.
# Requires: aws cli authed, docker running.
# ECR registry is derived from the current AWS account.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
ACCOUNT=$(aws sts get-caller-identity --query Account --output text --profile draios-dev)
REGISTRY="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"
IMAGE="${REGISTRY}/customer-portal/portal:2.5.10"

aws ecr describe-repositories --region "$REGION" --profile draios-dev \
  --repository-names customer-portal/portal >/dev/null 2>&1 \
  || aws ecr create-repository --region "$REGION" --profile draios-dev \
       --repository-name customer-portal/portal >/dev/null

aws ecr get-login-password --region "$REGION" --profile draios-dev \
  | docker login --username AWS --password-stdin "$REGISTRY"

docker build --platform linux/amd64 -t "$IMAGE" "$ROOT/app"
# ./scan.sh || true
docker push "$IMAGE"
echo "Pushed $IMAGE"
