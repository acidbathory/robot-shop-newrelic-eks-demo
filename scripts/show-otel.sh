#!/usr/bin/env bash
# Presenter helper — prove the tracing is genuinely OpenTelemetry, live.
# Walks: declarative CRDs -> zero-touch pod injection -> collector pipeline ->
# provenance in New Relic. Run on the EKS context.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/load-env.sh" >/dev/null
NS_OBS=observability; NS_APP=robot-shop
RS="'catalogue','cart','user','shipping','payment'"   # robot-shop auto-instrumented services (NRQL-quoted)

hr(){ printf '\n\033[1m== %s ==\033[0m\n' "$1"; }
nrql(){ curl -s -X POST "$NEW_RELIC_API_ENDPOINT" -H "Content-Type: application/json" -H "API-Key: $NEW_RELIC_USER_KEY" \
  -d "$(jq -n --argjson a "$NEW_RELIC_ACCOUNT_ID" --arg q "$1" '{query:"query($a:Int!,$q:Nrql!){actor{account(id:$a){nrql(query:$q){results}}}}",variables:{a:$a,q:$q}}')" \
  | jq -c '.data.actor.account.nrql.results'; }

hr "1. Declarative config — tracing is Kubernetes resources, not app code"
kubectl get opentelemetrycollector,instrumentation -n "$NS_OBS"

hr "2. Zero-touch injection — the Operator added the OTel SDK at pod startup"
POD=$(kubectl get pod -n "$NS_APP" -l service=cart -o name | head -1)
echo "init container: $(kubectl get "$POD" -n "$NS_APP" -o jsonpath='{.spec.initContainers[*].name}')"
kubectl get "$POD" -n "$NS_APP" -o jsonpath='{range .spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' \
  | grep -iE 'NODE_OPTIONS|OTEL_SERVICE_NAME|OTEL_EXPORTER_OTLP_ENDPOINT|OTEL_PROPAGATORS|OTEL_TRACES_SAMPLER='

hr "3. Collector — standard OTLP in, OTLP out (swap the exporter for any backend)"
kubectl get opentelemetrycollector nr -n "$NS_OBS" -o jsonpath='{.spec.config}' 2>/dev/null \
  | grep -iE 'otlp|exporters|otlphttp|endpoint|k8sattributes' | head -12 || \
  kubectl -n "$NS_OBS" get cm -l app.kubernetes.io/component=opentelemetry-collector -o jsonpath='{.items[0].data}' | head -c 400

hr "4a. Proof in New Relic — every span tagged instrumentation.provider=opentelemetry"
nrql "SELECT count(*) FROM Span WHERE instrumentation.provider='opentelemetry' AND service.name IN ($RS) FACET service.name SINCE 30 minutes ago"

hr "4b. The actual OTel instrumentation libraries producing the spans"
nrql "SELECT count(*) FROM Span WHERE service.name IN ($RS) FACET otel.library.name SINCE 30 minutes ago LIMIT 10"

hr "4c. OTel SDK language/version per service (polyglot via one Operator)"
nrql "SELECT latest(telemetry.sdk.language), latest(telemetry.sdk.version) FROM Span WHERE service.name IN ($RS) FACET service.name SINCE 30 minutes ago"

echo; echo "Talking point: zero app changes; upstream OTel SDK injected by annotation;"
echo "W3C traceparent propagation; one exporter line points at New Relic (or any OTLP backend)."
