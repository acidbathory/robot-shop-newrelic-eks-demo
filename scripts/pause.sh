#!/usr/bin/env bash
# Pause the demo to cut cost WITHOUT destroying it — scales the EKS nodegroup to 0.
# Stops all EC2 node charges + all pods (incl. chat-loadgen, so OpenAI calls stop).
# Keeps: control plane, all manifests/secrets, ELB URLs, NR dashboards/alerts/PagerDuty.
# Residual cost while paused: control plane (~$0.10/hr) + 2 ELBs + small EBS ≈ $3-4/day.
# Resume with scripts/resume.sh (~8-10 min).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/load-env.sh" >/dev/null
NG=ng-robotshop

echo "==> Scaling nodegroup $NG to 0 (cluster $CLUSTER, $AWS_REGION)"
eksctl scale nodegroup --cluster "$CLUSTER" --region "$AWS_REGION" --name "$NG" \
  --nodes 0 --nodes-min 0 --nodes-max 4

echo "==> Done. Nodes will terminate in ~2-3 min; pods stop with them."
echo "    Workloads, services/ELBs, secrets, and NR config all persist."
echo "    Resume for rehearsal:  bash scripts/resume.sh"
