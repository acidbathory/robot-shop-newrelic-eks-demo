#!/usr/bin/env bash
# Phase 6c — route the "Robot Shop on EKS" alert policy to PagerDuty, as code.
# Creates: AI-notifications Destination (PagerDuty service integration) + Channel
# + a Workflow that forwards this policy's issues to that channel.
#
# Needs a PagerDuty Events API v2 integration key:
#   security add-generic-password -a "$USER" -s pagerduty_integration_key -w "<key>" -U
# then re-run scripts/load-env.sh (which exports PAGERDUTY_INTEGRATION_KEY).
set -euo pipefail
set +o braceexpand                      # GraphQL {..,..} groups must not be brace-expanded
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/load-env.sh" >/dev/null
: "${NEW_RELIC_USER_KEY:?}"; : "${NEW_RELIC_ACCOUNT_ID:?}"
PD_KEY="${PAGERDUTY_INTEGRATION_KEY:-$(security find-generic-password -s pagerduty_integration_key -w 2>/dev/null || true)}"
: "${PD_KEY:?Set pagerduty_integration_key in the Keychain (Events API v2 integration key)}"
API="$NEW_RELIC_API_ENDPOINT"; KEY="$NEW_RELIC_USER_KEY"; ACCT="$NEW_RELIC_ACCOUNT_ID"
POLICY_NAME="Robot Shop on EKS"

gql() { curl -s -X POST "$API" -H "Content-Type: application/json" -H "API-Key: $KEY" -d "$1"; }

# 1. Find the policy id by name (created by alerts.sh).
echo "==> Looking up policy '$POLICY_NAME'"
POLICY_ID="$(gql "$(jq -n --argjson a "$ACCT" --arg n "$POLICY_NAME" \
  '{query:"query($a:Int!,$n:String){actor{account(id:$a){alerts{policiesSearch(searchCriteria:{name:$n}){policies{id name}}}}}}",variables:{a:$a,n:$n}}')" \
  | jq -r '.data.actor.account.alerts.policiesSearch.policies[0].id // empty')"
: "${POLICY_ID:?could not find policy '$POLICY_NAME' — run newrelic/alerts.sh first}"
echo "    policy id: $POLICY_ID"

# 2. Destination — PagerDuty service integration (auth token = the integration key).
echo "==> Creating PagerDuty destination"
DRESP="$(gql "$(jq -n --argjson a "$ACCT" --arg t "$PD_KEY" \
  '{query:"mutation($a:Int!,$t:SecureValue!){aiNotificationsCreateDestination(accountId:$a,destination:{type:PAGERDUTY_SERVICE_INTEGRATION,name:\"PagerDuty - Robot Shop\",properties:[],auth:{type:TOKEN,token:{prefix:\"Token token=\",token:$t}}}){destination{id} error{__typename ... on AiNotificationsResponseError{description} ... on AiNotificationsDataValidationError{details}}}}",variables:{a:$a,t:$t}}')")"
DEST_ID="$(echo "$DRESP" | jq -r '.data.aiNotificationsCreateDestination.destination.id // empty')"
[[ -z "$DEST_ID" ]] && { echo "destination failed:" >&2; echo "$DRESP" | jq -c '.data.aiNotificationsCreateDestination.error // .errors' >&2; exit 1; }
# Validate the token before building channel/workflow on top of it.
DSTATUS="$(gql "$(jq -n --argjson a "$ACCT" --arg d "$DEST_ID" '{query:"query($a:Int!,$d:[ID!]){actor{account(id:$a){aiNotifications{destinations(filters:{id:$d}){entities{status}}}}}}",variables:{a:$a,d:[$d]}}')" | jq -r '.data.actor.account.aiNotifications.destinations.entities[0].status // "UNKNOWN"')"
echo "    destination status: $DSTATUS"
echo "    destination id: $DEST_ID"

# 3. Channel — maps the issue to the PagerDuty Events API v2 payload.
echo "==> Creating PagerDuty channel"
CRESP="$(gql "$(jq -n --argjson a "$ACCT" --arg d "$DEST_ID" \
  '{query:"mutation($a:Int!,$d:ID!){aiNotificationsCreateChannel(accountId:$a,channel:{type:PAGERDUTY_SERVICE_INTEGRATION,name:\"PagerDuty - Robot Shop\",destinationId:$d,product:IINT,properties:[{key:\"summary\",value:\"{{ annotations.title.[0] }}\"},{key:\"customDetails\",value:\"{{ json annotations }}\"}]}){channel{id} error{__typename ... on AiNotificationsResponseError{description} ... on AiNotificationsDataValidationError{details}}}}",variables:{a:$a,d:$d}}')")"
CHAN_ID="$(echo "$CRESP" | jq -r '.data.aiNotificationsCreateChannel.channel.id // empty')"
[[ -z "$CHAN_ID" ]] && { echo "channel failed:" >&2; echo "$CRESP" | jq -c '.data.aiNotificationsCreateChannel.error // .errors' >&2; exit 1; }
echo "    channel id: $CHAN_ID"

# 4. Workflow — forward this policy's issues to the channel.
echo "==> Creating workflow"
WRESP="$(gql "$(jq -n --argjson a "$ACCT" --arg c "$CHAN_ID" --arg p "$POLICY_ID" \
  '{query:"mutation($a:Int!,$c:ID!,$p:String!){aiWorkflowsCreateWorkflow(accountId:$a,createWorkflowData:{name:\"Robot Shop -> PagerDuty\",workflowEnabled:true,destinationsEnabled:true,mutingRulesHandling:NOTIFY_ALL_ISSUES,issuesFilter:{name:\"policy\",type:FILTER,predicates:[{attribute:\"labels.policyIds\",operator:EXACTLY_MATCHES,values:[$p]}]},destinationConfigurations:[{channelId:$c}]}){workflow{id name} errors{description type}}}",variables:{a:$a,c:$c,p:$p}}')")"
WF_ID="$(echo "$WRESP" | jq -r '.data.aiWorkflowsCreateWorkflow.workflow.id // empty')"
[[ -z "$WF_ID" ]] && { echo "workflow failed:" >&2; echo "$WRESP" | jq -c '.data.aiWorkflowsCreateWorkflow.errors // .errors' >&2; exit 1; }
echo "    workflow id: $WF_ID"

echo "==> Done. Policy '$POLICY_NAME' now pages PagerDuty via workflow $WF_ID."
echo "    Test it: kubectl scale deploy/catalogue --replicas=0 -n robot-shop  (then scale back to 1)"
