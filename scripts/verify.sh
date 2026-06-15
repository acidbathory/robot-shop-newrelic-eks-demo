#!/usr/bin/env bash
# Confirm every telemetry signal is flowing into New Relic via NerdGraph NRQL.
# Green = data present in the last 30 minutes.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/load-env.sh" >/dev/null
: "${NEW_RELIC_USER_KEY:?}"; : "${NEW_RELIC_ACCOUNT_ID:?}"

run_nrql() {  # $1 = NRQL -> prints the first numeric result
  local q="$1"
  curl -s -X POST "$NEW_RELIC_API_ENDPOINT" \
    -H "Content-Type: application/json" -H "API-Key: $NEW_RELIC_USER_KEY" \
    -d "$(jq -n --argjson a "$NEW_RELIC_ACCOUNT_ID" --arg q "$q" \
        '{query:"query($a:Int!,$q:Nrql!){actor{account(id:$a){nrql(query:$q){results}}}}",variables:{a:$a,q:$q}}')" \
    | jq -r '.data.actor.account.nrql.results[0] | (.[] // 0)' 2>/dev/null | head -1
}

check() {  # $1=label  $2=NRQL  $3=min
  local v; v="$(run_nrql "$2")"; v="${v:-0}"
  local ok; ok=$(awk -v v="$v" -v m="$3" 'BEGIN{print (v+0>=m+0)?"PASS":"FAIL"}')
  printf "  [%s] %-34s = %s\n" "$ok" "$1" "$v"
}

echo "== New Relic signal check (cluster robot-shop-eks, last 30m) =="
check "K8s pods"        "SELECT uniqueCount(podName) FROM K8sPodSample WHERE clusterName='robot-shop-eks' SINCE 30 minutes ago" 1
check "Pod logs"        "SELECT count(*) FROM Log WHERE cluster_name='robot-shop-eks' SINCE 30 minutes ago" 1
check "APM/trace spans" "SELECT uniqueCount(service.name) FROM Span SINCE 30 minutes ago" 1
check "AI completions"  "SELECT count(*) FROM LlmChatCompletionSummary SINCE 30 minutes ago" 1
check "AI tokens"       "SELECT sum(response.usage.total_tokens) FROM LlmChatCompletionSummary SINCE 30 minutes ago" 1
check "K8s events"      "SELECT count(*) FROM InfrastructureEvent WHERE clusterName='robot-shop-eks' SINCE 60 minutes ago" 1
echo "== done =="
