#!/usr/bin/env bash
# Builds the portal image for linux/amd64 and pushes to ECR.
# Requires: aws cli authed, docker running.
# ECR registry is derived from the current AWS account.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
ACCOUNT=$(aws sts get-caller-identity --query Account --output text --profile draios-dev)
REGISTRY="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"
IMAGE="${REGISTRY}/golden-demo/portal:vuln"

aws ecr describe-repositories --region "$REGION" --profile draios-dev \
  --repository-names golden-demo/portal >/dev/null 2>&1 \
  || aws ecr create-repository --region "$REGION" \
       --repository-name golden-demo/portal >/dev/null

aws ecr get-login-password --region "$REGION" --profile draios-dev \
  | docker login --username AWS --password-stdin "$REGISTRY"

docker build --platform linux/amd64 -t "$IMAGE" "$ROOT/app"
./scan.sh || true
docker push "$IMAGE"
echo "Pushed $IMAGE"
