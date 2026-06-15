#!/usr/bin/env bash
# Phase 5b — deploy the AI assistant + chat loadgen with secrets.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/load-env.sh" >/dev/null
NS=ai-assistant
IMAGE="$(cat "$ROOT/ai-assistant/.image" 2>/dev/null || echo "$ECR_REGISTRY/ai-assistant:latest")"

: "${OPENAI_API_KEY:?OPENAI_API_KEY not set — add it to the Keychain (openai_api_key) and re-run load-env.sh}"

echo "==> Namespace + secrets"
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic ai-assistant-secrets -n "$NS" \
  --from-literal=nrLicenseKey="$NEW_RELIC_INGEST_KEY" \
  --from-literal=openaiApiKey="$OPENAI_API_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Deploy (image: $IMAGE)"
sed "s#__IMAGE__#${IMAGE}#g" "$ROOT/ai-assistant/k8s/deployment.yaml" | kubectl apply -f -
kubectl apply -f "$ROOT/ai-assistant/k8s/chat-loadgen.yaml"
kubectl rollout status deploy/ai-assistant -n "$NS" --timeout=3m

echo "==> Waiting for LoadBalancer URL..."
for i in $(seq 1 30); do
  LB=$(kubectl get svc ai-assistant -n "$NS" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  [ -n "$LB" ] && break; sleep 10
done
echo "    AI assistant URL: http://${LB:-<pending>}/"
