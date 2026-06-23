#!/usr/bin/env bash
set -euo pipefail

export AWS_PROFILE="draios-dev"

REGION="ap-southeast-2"
ACCOUNT="059797578166"
REPO="golden-demo/claude-demo"
REGISTRY="$ACCOUNT.dkr.ecr.$REGION.amazonaws.com"

echo "==> Authenticating with ECR..."
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"

echo "==> Creating ECR repo if needed..."
aws ecr describe-repositories --region "$REGION" --repository-names "$REPO" >/dev/null 2>&1 \
  || aws ecr create-repository --region "$REGION" --repository-name "$REPO"

echo "==> Finding latest version tag..."
LATEST=$(aws ecr list-images --region "$REGION" --repository-name "$REPO" \
  --query 'imageIds[].imageTag' --output text 2>/dev/null \
  | tr '\t' '\n' | grep '^v[0-9]*$' | sort -V | tail -1 || true)

if [[ -z "$LATEST" ]]; then
  NEXT="v1"
else
  NEXT="v$(( ${LATEST#v} + 1 ))"
fi

IMAGE="$REGISTRY/$REPO:$NEXT"
echo "==> Building $IMAGE ..."
docker build --platform linux/amd64 -t "$IMAGE" "$(dirname "$0")"

echo "==> Pushing..."
docker push "$IMAGE"

echo "==> Updating pod manifests to $NEXT ..."
DIR="$(dirname "$0")"
sed -i '' "s|$REGISTRY/$REPO:v[0-9]*|$IMAGE|g" "$DIR/k8s/10-pod.yaml" "$DIR/k8s/10-pod-nocreds.yaml"

echo "Done: $IMAGE"
