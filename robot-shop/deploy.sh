#!/usr/bin/env bash
# Phase 3 — deploy robot-shop + load generator to the EKS cluster.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS=robot-shop

echo "==> Deploying robot-shop chart to ns/$NS"
helm upgrade --install robot-shop "$ROOT/robot-shop/helm" \
  -n "$NS" --create-namespace \
  -f "$ROOT/robot-shop/values-eks.yaml" \
  --wait --timeout 10m

echo "==> Deploying load generator"
kubectl apply -n "$NS" -f "$ROOT/robot-shop/load-deployment.yaml"

echo "==> Pods:"
kubectl get pods -n "$NS"

echo "==> Waiting for web LoadBalancer URL..."
for i in $(seq 1 30); do
  LB=$(kubectl get svc web -n "$NS" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  [ -n "$LB" ] && break
  sleep 10
done
echo "    robot-shop URL: http://${LB:-<pending>}:8080/"
