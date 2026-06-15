#!/usr/bin/env bash
# Tear down everything created for the demo. Prompts before the expensive bits.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/load-env.sh" >/dev/null

confirm() { read -r -p "$1 [y/N] " a; [[ "$a" =~ ^[Yy]$ ]]; }

echo "This will remove the demo workloads and (optionally) the EKS cluster."

# Delete LoadBalancer services first so their ELBs are released before cluster delete.
kubectl delete svc ai-assistant -n ai-assistant --ignore-not-found
kubectl delete svc web -n robot-shop --ignore-not-found

echo "==> Uninstalling workloads"
kubectl delete -f "$ROOT/ai-assistant/k8s/chat-loadgen.yaml" --ignore-not-found
kubectl delete namespace ai-assistant --ignore-not-found
helm uninstall robot-shop -n robot-shop 2>/dev/null || true
kubectl delete namespace robot-shop --ignore-not-found
kubectl delete -f "$ROOT/observability/instrumentation.yaml" --ignore-not-found 2>/dev/null || true
helm uninstall opentelemetry-operator -n observability 2>/dev/null || true
helm uninstall newrelic-bundle -n newrelic 2>/dev/null || true
helm uninstall cert-manager -n cert-manager 2>/dev/null || true
kubectl delete namespace observability newrelic cert-manager --ignore-not-found

if confirm "Delete the EKS cluster '$CLUSTER' (releases all AWS billing)?"; then
  eksctl delete cluster --name "$CLUSTER" --region "$AWS_REGION" --wait
  if confirm "Delete the ECR 'ai-assistant' repository too?"; then
    aws ecr delete-repository --repository-name ai-assistant --region "$AWS_REGION" --force >/dev/null 2>&1 || true
  fi
fi

echo "==> Note: New Relic dashboards/alerts persist. Delete them in the UI, or by GUID via NerdGraph."
echo "==> Teardown complete."
