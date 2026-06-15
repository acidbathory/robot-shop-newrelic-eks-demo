#!/usr/bin/env bash
# Enable or disable the demo's synthetic monitors via NerdGraph.
#   usage: bash newrelic/toggle-synthetics.sh <ENABLED|DISABLED>
# Used by scripts/pause.sh (DISABLED) and scripts/resume.sh (ENABLED): while the cluster is
# paused the storefront/AI endpoints are down, so leaving synthetics ENABLED would fail every
# check and page PagerDuty for the whole pause. Discovers monitors by tag (demo=robot-shop),
# so it keeps working after a rebuild even though GUIDs change.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/load-env.sh" >/dev/null
: "${NEW_RELIC_USER_KEY:?}"

STATUS="${1:-}"
[[ "$STATUS" == "ENABLED" || "$STATUS" == "DISABLED" ]] || { echo "usage: $0 <ENABLED|DISABLED>" >&2; exit 2; }

gql() { curl -s https://api.newrelic.com/graphql -H "API-Key: $NEW_RELIC_USER_KEY" -H 'Content-Type: application/json' --data "$(jq -nc --arg q "$1" '{query:$q}')"; }

# Map monitorType -> the type-specific update mutation (no generic update mutation exists).
mutation_for() {
  case "$1" in
    SIMPLE)     echo "syntheticsUpdateSimpleMonitor" ;;
    BROWSER)    echo "syntheticsUpdateSimpleBrowserMonitor" ;;
    SCRIPT_API) echo "syntheticsUpdateScriptApiMonitor" ;;
    *)          echo "" ;;
  esac
}

echo "==> Setting demo synthetic monitors to $STATUS"
ROWS="$(gql '{ actor { entitySearch(query: "domain='"'"'SYNTH'"'"' AND tags.demo='"'"'robot-shop'"'"'") { results { entities { guid name ... on SyntheticMonitorEntityOutline { monitorType } } } } } }' \
  | jq -r '.data.actor.entitySearch.results.entities[]? | "\(.monitorType)\t\(.guid)\t\(.name)"')"
[[ -z "$ROWS" ]] && { echo "    (no monitors found with tag demo=robot-shop — nothing to do)"; exit 0; }

while IFS=$'\t' read -r mtype guid name; do
  mut="$(mutation_for "$mtype")"
  [[ -z "$mut" ]] && { echo "    [skip] $name (unhandled type $mtype)"; continue; }
  resp="$(gql "mutation { $mut(guid:\"$guid\", monitor:{status:$STATUS}){ monitor{status} errors{description} } }")"
  st="$(echo "$resp" | jq -r ".data.$mut.monitor.status // empty")"
  if [[ "$st" == "$STATUS" ]]; then echo "    [ok] $name -> $st"; else echo "    [FAIL] $name"; echo "$resp" | jq -c ".data.$mut.errors // .errors // ." >&2; fi
done <<< "$ROWS"
echo "==> Done."
