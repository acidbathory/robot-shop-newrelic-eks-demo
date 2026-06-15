#!/usr/bin/env bash
# Phase 2 — install New Relic's nri-bundle (K8s infra, KSM, events, logs, prometheus).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/load-env.sh" >/dev/null

helm repo add newrelic https://helm-charts.newrelic.com >/dev/null 2>&1 || true
helm repo update newrelic >/dev/null

echo "==> Installing nri-bundle (cluster=$CLUSTER)"
helm upgrade --install newrelic-bundle newrelic/nri-bundle \
  --namespace newrelic --create-namespace \
  --set global.licenseKey="$NEW_RELIC_INGEST_KEY" \
  --set global.cluster="$CLUSTER" \
  -f "$ROOT/newrelic/values-nri-bundle.yaml" \
  --wait --timeout 8m

echo "==> newrelic ns pods:"
kubectl get pods -n newrelic
echo "==> Done. Allow ~3-5 min for data to appear in New Relic (cluster '$CLUSTER')."
