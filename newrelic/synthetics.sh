#!/usr/bin/env bash
# Phase 6c — create New Relic Synthetic monitors via NerdGraph (proactive, outside-in checks).
# Creates three monitor types against the live ELBs:
#   1. SIMPLE BROWSER  -> robot-shop storefront (real Chrome: availability + page load + screenshot)
#   2. SIMPLE (ping)   -> ai-assistant /healthz (lightest liveness check)
#   3. SCRIPT_API      -> ai-assistant /chat (POSTs a real question, asserts 200 + non-empty reply;
#                         exercises the full OpenAI path end-to-end and keeps AI Monitoring fed)
# Locations: AWS_AP_SOUTH_1 (next to the cluster) + AWS_US_EAST_1 (geo diversity / account DC).
# NOTE: creates fresh monitors each run (no upsert). Delete old ones in the UI if re-running.
# The matching "Synthetic monitor failure" alert condition lives in newrelic/alerts.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/load-env.sh" >/dev/null
: "${NEW_RELIC_USER_KEY:?}"; : "${NEW_RELIC_ACCOUNT_ID:?}"
API="$NEW_RELIC_API_ENDPOINT"; KEY="$NEW_RELIC_USER_KEY"; ACCT="$NEW_RELIC_ACCOUNT_ID"
LOCATIONS='["AWS_AP_SOUTH_1","AWS_US_EAST_1"]'

# Discover the live LoadBalancer hostnames from the cluster.
WEB_HOST="$(kubectl get svc web -n robot-shop -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
AI_HOST="$(kubectl get svc ai-assistant -n ai-assistant -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
[[ -z "$WEB_HOST" || -z "$AI_HOST" ]] && { echo "ERROR: could not read web/ai-assistant ELB hostnames — is the cluster up (scripts/resume.sh)?" >&2; exit 1; }
WEB_URI="http://${WEB_HOST}:8080/"
AI_BASE="http://${AI_HOST}/"
echo "==> Targets: storefront=$WEB_URI  ai=$AI_BASE"

gql() { curl -s -X POST "$API" -H "Content-Type: application/json" -H "API-Key: $KEY" -d "$1"; }
report() { # <label> <json-response> <data-path>
  local id; id="$(echo "$2" | jq -r "$3.monitor.guid // empty")"
  if [[ -n "$id" ]]; then echo "    [ok] $1 (guid $id)"; else echo "    [FAIL] $1"; echo "$2" | jq -c "$3.errors // .errors // ." >&2; fi
}

echo "==> 1/3 Browser monitor: robot-shop storefront"
R="$(gql "$(jq -n --argjson a "$ACCT" --arg uri "$WEB_URI" --argjson loc "$LOCATIONS" \
  '{query:"mutation($a:Int!,$uri:String!,$loc:[String]){syntheticsCreateSimpleBrowserMonitor(accountId:$a,monitor:{name:\"robot-shop storefront (browser)\",uri:$uri,period:EVERY_5_MINUTES,status:ENABLED,locations:{public:$loc},runtime:{runtimeType:\"CHROME_BROWSER\",runtimeTypeVersion:\"100\",scriptLanguage:\"JAVASCRIPT\"},tags:[{key:\"demo\",values:[\"robot-shop\"]}]}){monitor{guid name}errors{description type}}}",variables:{a:$a,uri:$uri,loc:$loc}}')")"
report "storefront (browser)" "$R" ".data.syntheticsCreateSimpleBrowserMonitor"

echo "==> 2/3 Ping monitor: ai-assistant /healthz"
R="$(gql "$(jq -n --argjson a "$ACCT" --arg uri "${AI_BASE}healthz" --argjson loc "$LOCATIONS" \
  '{query:"mutation($a:Int!,$uri:String!,$loc:[String]){syntheticsCreateSimpleMonitor(accountId:$a,monitor:{name:\"ai-assistant health (ping)\",uri:$uri,period:EVERY_5_MINUTES,status:ENABLED,locations:{public:$loc},tags:[{key:\"demo\",values:[\"robot-shop\"]}]}){monitor{guid name}errors{description type}}}",variables:{a:$a,uri:$uri,loc:$loc}}')")"
report "ai health (ping)" "$R" ".data.syntheticsCreateSimpleMonitor"

echo "==> 3/3 Scripted API monitor: ai-assistant /chat (end-to-end OpenAI path)"
read -r -d '' SCRIPT <<EOF || true
const assert = require('assert');
const got = require('got');

const URL = '${AI_BASE}chat';
const payload = { message: 'What do you recommend for a beginner robotics enthusiast?' };

const response = await got.post(URL, { json: payload, responseType: 'json', timeout: { request: 25000 } });
assert.strictEqual(response.statusCode, 200, 'Expected HTTP 200 from /chat, got ' + response.statusCode);
assert.ok(response.body && response.body.reply && response.body.reply.length > 0, 'Expected a non-empty assistant reply');
console.log('AI assistant replied with ' + response.body.reply.length + ' chars');
EOF
R="$(gql "$(jq -n --argjson a "$ACCT" --arg script "$SCRIPT" --argjson loc "$LOCATIONS" \
  '{query:"mutation($a:Int!,$script:String!,$loc:[String]){syntheticsCreateScriptApiMonitor(accountId:$a,monitor:{name:\"ai-assistant chat e2e (api)\",period:EVERY_5_MINUTES,status:ENABLED,locations:{public:$loc},runtime:{runtimeType:\"NODE_API\",runtimeTypeVersion:\"16.10\",scriptLanguage:\"JAVASCRIPT\"},script:$script,tags:[{key:\"demo\",values:[\"robot-shop\"]}]}){monitor{guid name}errors{description type}}}",variables:{a:$a,script:$script,loc:$loc}}')")"
report "ai chat e2e (api)" "$R" ".data.syntheticsCreateScriptApiMonitor"

echo "==> Done. Monitors run from $LOCATIONS every 5 min."
echo "    Failures route through the 'Robot Shop on EKS' policy -> PagerDuty (see newrelic/alerts.sh)."
echo "    View: New Relic > Synthetic monitoring. Data: SELECT * FROM SyntheticCheck SINCE 30 minutes ago"
