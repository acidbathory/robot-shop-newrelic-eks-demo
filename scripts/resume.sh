#!/usr/bin/env bash
# Resume the demo after pause.sh — scales the nodegroup back to 3 and waits for
# everything to come healthy. ~8-10 min total.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/load-env.sh" >/dev/null
NG=ng-robotshop

echo "==> Scaling nodegroup $NG back to 3"
eksctl scale nodegroup --cluster "$CLUSTER" --region "$AWS_REGION" --name "$NG" \
  --nodes 3 --nodes-min 3 --nodes-max 4

echo "==> Refreshing kubeconfig + context (avoids the OrbStack context trap)"
aws eks update-kubeconfig --name "$CLUSTER" --region "$AWS_REGION" >/dev/null
kubectl config use-context "arn:aws:eks:${AWS_REGION}:926634327293:cluster/${CLUSTER}" >/dev/null

echo "==> Waiting for nodes Ready"
until [ "$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready ')" -ge 3 ]; do sleep 10; done
kubectl get nodes

echo "==> Waiting for key deployments to reschedule"
for d in catalogue cart user shipping payment web; do
  kubectl rollout status deploy/"$d" -n robot-shop --timeout=5m || true
done
kubectl rollout status deploy/ai-assistant -n ai-assistant --timeout=5m || true

# Re-enable synthetic monitors (pause.sh disabled them so they wouldn't page while down).
echo "==> Re-enabling synthetic monitors"
bash "$ROOT/newrelic/toggle-synthetics.sh" ENABLED || echo "    (warning: could not re-enable synthetics — enable them in the UI)"

echo "==> URLs (ELBs are preserved across pause/resume):"
echo "    robot-shop:   http://$(kubectl get svc web -n robot-shop -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null):8080/"
echo "    ai-assistant: http://$(kubectl get svc ai-assistant -n ai-assistant -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)/"
echo "==> Give telemetry ~3-5 min, then: bash scripts/verify.sh"
