#!/usr/bin/env bash
# Phase 4a — install cert-manager + OpenTelemetry Operator, the New Relic secret,
# the collector, and the Instrumentation CR.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/load-env.sh" >/dev/null
NS=observability

echo "==> cert-manager (operator webhook dependency)"
helm repo add jetstack https://charts.jetstack.io >/dev/null 2>&1 || true
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts >/dev/null 2>&1 || true
helm repo update jetstack open-telemetry >/dev/null
helm upgrade --install cert-manager jetstack/cert-manager \
  -n cert-manager --create-namespace --set crds.enabled=true --wait --timeout 5m

echo "==> OpenTelemetry Operator"
helm upgrade --install opentelemetry-operator open-telemetry/opentelemetry-operator \
  -n "$NS" --create-namespace \
  --set "manager.collectorImage.repository=otel/opentelemetry-collector-contrib" \
  --wait --timeout 5m

echo "==> New Relic ingest secret (for collector exporter)"
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic newrelic-keys -n "$NS" \
  --from-literal=ingestKey="$NEW_RELIC_INGEST_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Collector + Instrumentation + RBAC"
# OTLP endpoint substituted into the collector CR at apply time.
sed "s#__NR_OTLP_ENDPOINT__#${NEW_RELIC_OTLP_ENDPOINT}#g" "$ROOT/observability/otel-collector.yaml" | kubectl apply -f -
kubectl apply -f "$ROOT/observability/rbac.yaml"
kubectl apply -f "$ROOT/observability/instrumentation.yaml"

echo "==> Waiting for collector to be ready"
kubectl rollout status deploy/nr-collector -n "$NS" --timeout=3m || true
kubectl get pods -n "$NS"
