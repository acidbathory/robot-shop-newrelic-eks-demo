#!/usr/bin/env bash
# Phase 1 — provision the EKS cluster and wire kubeconfig + ECR.
# Idempotent-ish: skips creation if the cluster already exists.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/load-env.sh" >/dev/null

echo "==> Region: $AWS_REGION  Cluster: $CLUSTER"

if eksctl get cluster --name "$CLUSTER" --region "$AWS_REGION" >/dev/null 2>&1; then
  echo "==> Cluster $CLUSTER already exists; skipping create."
else
  echo "==> Creating cluster (this takes ~15-20 min)..."
  eksctl create cluster -f "$ROOT/eks/cluster.yaml"
fi

echo "==> Updating kubeconfig"
aws eks update-kubeconfig --name "$CLUSTER" --region "$AWS_REGION"

echo "==> Nodes:"
kubectl get nodes -o wide

echo "==> Creating ECR repo for the AI assistant"
aws ecr describe-repositories --repository-names ai-assistant --region "$AWS_REGION" >/dev/null 2>&1 \
  || aws ecr create-repository --repository-name ai-assistant --region "$AWS_REGION" >/dev/null
echo "    ECR registry: $ECR_REGISTRY"

echo "==> Done. Context: $(kubectl config current-context)"
