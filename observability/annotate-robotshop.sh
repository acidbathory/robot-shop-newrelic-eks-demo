#!/usr/bin/env bash
# Phase 4b — annotate robot-shop deployments so the OTel Operator injects
# auto-instrumentation. Triggers a rollout; the injected SDK exports to the nr collector.
#
# Language coverage (OTel auto-instrumentation supports java/nodejs/python/dotnet):
#   shipping            -> java
#   cart catalogue user -> nodejs
#   payment             -> python
# Not auto-instrumented (documented honestly in the demo guide):
#   dispatch (go), ratings (php), web (nginx), mongodb/mysql/redis/rabbitmq (infra).
set -euo pipefail
NS=robot-shop
INSTR="observability/robot-shop"   # <instrumentation-namespace>/<name>

annotate() {  # $1=deployment  $2=lang
  echo "==> $1: inject-$2"
  kubectl patch deployment "$1" -n "$NS" --type merge -p \
    "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"instrumentation.opentelemetry.io/inject-$2\":\"$INSTR\"}}}}}"
}

annotate shipping  java
annotate cart      nodejs
annotate catalogue nodejs
annotate user      nodejs
annotate payment   python

echo "==> Waiting for rollouts"
for d in shipping cart catalogue user payment; do
  kubectl rollout status deploy/"$d" -n "$NS" --timeout=3m || true
done
echo "==> Done. Distributed traces should appear in New Relic within a few minutes."
