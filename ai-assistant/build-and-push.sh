#!/usr/bin/env bash
# Phase 5a — build the AI assistant image and push to ECR (linux/amd64 for EKS nodes).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/load-env.sh" >/dev/null
IMAGE="$ECR_REGISTRY/ai-assistant:latest"

echo "==> ECR login"
aws ecr describe-repositories --repository-names ai-assistant --region "$AWS_REGION" >/dev/null 2>&1 \
  || aws ecr create-repository --repository-name ai-assistant --region "$AWS_REGION" >/dev/null
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_REGISTRY"

echo "==> Build + push $IMAGE"
docker buildx build --platform linux/amd64 -t "$IMAGE" --push "$ROOT/ai-assistant"
echo "$IMAGE" > "$ROOT/ai-assistant/.image"
echo "==> Pushed $IMAGE"
