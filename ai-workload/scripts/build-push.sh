#!/usr/bin/env bash
# Builds the langchain AI workload image for linux/amd64 and pushes to ECR.
# Requires: aws cli authed (profile draios-dev), docker running.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REGION=ap-southeast-2
ACCOUNT=$(aws sts get-caller-identity --query Account --output text --profile draios-dev)
REGISTRY="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"
IMAGE="${REGISTRY}/ai-workload/langchain:1.0.2"

aws ecr describe-repositories --region "$REGION" --profile draios-dev \
  --repository-names ai-workload/langchain >/dev/null 2>&1 \
  || aws ecr create-repository --region "$REGION" --profile draios-dev \
       --repository-name ai-workload/langchain >/dev/null

aws ecr get-login-password --region "$REGION" --profile draios-dev \
  | docker login --username AWS --password-stdin "$REGISTRY"

docker build --platform linux/amd64 -t "$IMAGE" "$ROOT"
docker push "$IMAGE"
echo "Pushed $IMAGE"
