#!/usr/bin/env bash
# Phase 6b — create an alert policy + NRQL conditions via NerdGraph.
# Idempotent-ish: always creates a fresh policy named below (delete old ones in UI if re-running).
set -euo pipefail
set +o braceexpand   # GraphQL queries contain {..,..} groups; keep bash from expanding them
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/load-env.sh" >/dev/null
: "${NEW_RELIC_USER_KEY:?}"; : "${NEW_RELIC_ACCOUNT_ID:?}"
API="$NEW_RELIC_API_ENDPOINT"; KEY="$NEW_RELIC_USER_KEY"; ACCT="$NEW_RELIC_ACCOUNT_ID"
POLICY_NAME="Robot Shop on EKS"

gql() { curl -s -X POST "$API" -H "Content-Type: application/json" -H "API-Key: $KEY" -d "$1"; }

echo "==> Creating policy '$POLICY_NAME'"
PRESP="$(gql "$(jq -n --argjson a "$ACCT" --arg n "$POLICY_NAME" \
  '{query:"mutation($a:Int!,$n:String!){alertsPolicyCreate(accountId:$a,policy:{name:$n,incidentPreference:PER_CONDITION}){id}}",variables:{a:$a,n:$n}}')")"
POLICY_ID="$(echo "$PRESP" | jq -r '.data.alertsPolicyCreate.id // empty')"
[[ -z "$POLICY_ID" ]] && { echo "policy create failed:" >&2; echo "$PRESP" | jq . >&2; exit 1; }
echo "    policy id: $POLICY_ID"

# create_condition <name> <nrql> <operator> <threshold> <duration_sec>
create_condition() {
  local name="$1" nrql="$2" op="$3" thr="$4" dur="$5"
  local resp
  resp="$(gql "$(jq -n --argjson a "$ACCT" --arg p "$POLICY_ID" --arg n "$name" --arg q "$nrql" \
      --arg op "$op" --argjson thr "$thr" --argjson dur "$dur" \
    '{query:"mutation($a:Int!,$p:ID!,$n:String!,$q:Nrql!,$op:AlertsNrqlConditionTermsOperator!,$thr:Float!,$dur:Seconds!){alertsNrqlConditionStaticCreate(accountId:$a,policyId:$p,condition:{name:$n,enabled:true,nrql:{query:$q},signal:{aggregationWindow:60,aggregationMethod:EVENT_FLOW,aggregationDelay:120},terms:[{threshold:$thr,thresholdOccurrences:AT_LEAST_ONCE,thresholdDuration:$dur,operator:$op,priority:CRITICAL}],violationTimeLimitSeconds:86400}){id name}}",
      variables:{a:$a,p:$p,n:$n,q:$q,op:$op,thr:$thr,dur:$dur}}')")"
  local id; id="$(echo "$resp" | jq -r '.data.alertsNrqlConditionStaticCreate.id // empty')"
  if [[ -n "$id" ]]; then echo "    [ok] $name (id $id)"; else echo "    [FAIL] $name"; echo "$resp" | jq -c '.errors // .data' >&2; fi
}

echo "==> Creating NRQL conditions"
create_condition "Pod crashloop (restarts)" \
  "SELECT max(restartCount) FROM K8sContainerSample WHERE clusterName = 'robot-shop-eks' FACET podName" ABOVE 3 300
create_condition "Pod not ready" \
  "SELECT latest(isReady) FROM K8sPodSample WHERE clusterName = 'robot-shop-eks' FACET podName" BELOW 1 300
create_condition "Service error rate %" \
  "SELECT percentage(count(*), WHERE otel.status_code = 'ERROR') FROM Span WHERE span.kind = 'server' FACET service.name" ABOVE 10 300
create_condition "API p95 latency (ms)" \
  "SELECT percentile(duration.ms, 95) FROM Span WHERE span.kind = 'server' FACET service.name" ABOVE 1500 300
create_condition "LLM hourly cost guard (USD)" \
  "SELECT filter(sum(token_count), WHERE is_response IS FALSE)/1e6*0.15 + filter(sum(token_count), WHERE is_response IS TRUE)/1e6*0.60 FROM LlmChatCompletionMessage" ABOVE 1 300
create_condition "Log error surge" \
  "SELECT count(*) FROM Log WHERE cluster_name = 'robot-shop-eks' AND (level = 'error' OR message LIKE '%Exception%')" ABOVE 50 300

echo "==> Done. Policy '$POLICY_NAME' ($POLICY_ID) created with 6 conditions."
