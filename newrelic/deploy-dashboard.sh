#!/usr/bin/env bash
# Phase 6a — create the full-stack dashboard in New Relic from dashboard.json.
# __ACCOUNT_ID__ in the JSON is substituted with the real account id at deploy time.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/load-env.sh" >/dev/null
: "${NEW_RELIC_USER_KEY:?}"; : "${NEW_RELIC_ACCOUNT_ID:?}"

DASH="$(sed "s/__ACCOUNT_ID__/${NEW_RELIC_ACCOUNT_ID}/g" "$ROOT/newrelic/dashboard.json")"
PAYLOAD="$(jq -n --argjson acct "$NEW_RELIC_ACCOUNT_ID" --argjson d "$DASH" \
  '{query:"mutation($a:Int!,$dash:DashboardInput!){dashboardCreate(accountId:$a,dashboard:$dash){entityResult{guid name} errors{description type}}}",
    variables:{a:$acct,dash:$d}}')"

RESP="$(curl -s -X POST "$NEW_RELIC_API_ENDPOINT" \
  -H "Content-Type: application/json" -H "API-Key: $NEW_RELIC_USER_KEY" -d "$PAYLOAD")"
echo "$RESP" | jq '.data.dashboardCreate.errors // empty'

GUID="$(echo "$RESP" | jq -r '.data.dashboardCreate.entityResult.guid // empty')"
[[ -z "$GUID" ]] && { echo "no guid — see response:" >&2; echo "$RESP" | jq . >&2; exit 1; }
PERMALINK="$(curl -s -X POST "$NEW_RELIC_API_ENDPOINT" \
  -H "Content-Type: application/json" -H "API-Key: $NEW_RELIC_USER_KEY" \
  -d "$(jq -n --arg g "$GUID" '{query:"{ actor { entity(guid:$g){ permalink } } }",variables:{g:$g}}')" \
  | jq -r '.data.actor.entity.permalink // empty')"
echo; echo "Dashboard: ${PERMALINK:-$GUID}"
