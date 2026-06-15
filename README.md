# New Relic Demo Certification — EKS · robot-shop · Claude AI Observability

A full-stack New Relic showcase built for a demo certification. It runs the
[Instana **robot-shop**](https://github.com/instana/robot-shop) polyglot microservices app on
**Amazon EKS**, adds a **Claude-powered shop-assistant chatbot**, and lights up New Relic
across **Kubernetes, APM, distributed tracing, logs, and AI Monitoring** — with
dashboards and alerts defined as code.

```
 EKS (ap-south-1)
  ├─ robot-shop      web · catalogue · cart · user · shipping · payment · ratings ·
  │                  dispatch · mongodb · mysql · redis · rabbitmq · loadgen
  │                    └─ OTel auto-instrumentation (java / node / python)
  ├─ ai-assistant    Claude shop-assistant (FastAPI + anthropic SDK + NR Python APM agent)
  ├─ observability   OTel Collector (OTLP → New Relic) + OpenTelemetry Operator
  └─ newrelic        nri-bundle: infra · kube-state-metrics · kube-events · logs · prometheus
 All telemetry → New Relic US (otlp.nr-data.net / api.newrelic.com)  ·  account 8059020
```

## New Relic surfaces highlighted
| # | Capability | Source |
|---|---|---|
| 1 | Kubernetes cluster explorer + infrastructure | nri-bundle (infra agent, kube-state-metrics) |
| 2 | Kubernetes events | nri-kube-events |
| 3 | Log forwarding (pod logs) | newrelic-logging (Fluent Bit) |
| 4 | APM + distributed tracing | robot-shop via OTel auto-instrumentation |
| 5 | AI Monitoring (tokens, cost, model, response) | Claude shop-assistant via NR Python APM agent |
| 6 | Dashboards as code | NerdGraph (`newrelic/dashboard.json`) |
| 7 | NRQL alerts | NerdGraph (`newrelic/alerts.sh`) |

## Layout
```
eks/            eksctl ClusterConfig + provisioning scripts
newrelic/       nri-bundle values/install, dashboard.json, alerts, deploy scripts
robot-shop/     vendored upstream Helm chart + values
observability/  OTel Operator install, collector config, Instrumentation CRD
ai-assistant/   Claude shop-assistant service (FastAPI), Dockerfile, k8s manifests, loadgen
demo/           demo-flow.md, demo-guide.md
scripts/        load-env.sh, deploy/verify/teardown helpers
```

## Quickstart
```bash
bash scripts/load-env.sh          # build .env from macOS Keychain
# Phase 1: provision EKS
eksctl create cluster -f eks/cluster.yaml
# Phase 2: New Relic K8s integration
bash newrelic/install-nri-bundle.sh
# Phase 3: robot-shop
helm upgrade --install robot-shop robot-shop/helm -n robot-shop --create-namespace
# Phase 4: tracing  · Phase 5: AI chatbot  · Phase 6: dashboards+alerts
# (see per-phase scripts)
bash scripts/verify.sh            # confirm all signals in New Relic
```

## Secrets
Keys live only in the **macOS Keychain** and a **gitignored `.env`** (and as in-cluster
Kubernetes Secrets). Nothing sensitive is committed. See `.env.example`.

## Teardown
```bash
bash scripts/teardown.sh          # eksctl delete cluster + helm uninstalls + cleanup
```

> ⚠️ Cost: EKS control plane + 3× t3.large ≈ $10–12/day in ap-south-1. Tear down when done.

## Build status
- [x] Phase 0 — repo + tooling bootstrap
- [ ] Phase 1 — EKS cluster
- [ ] Phase 2 — nri-bundle
- [ ] Phase 3 — robot-shop
- [ ] Phase 4 — OTel tracing
- [ ] Phase 5 — Claude shop-assistant + AI Monitoring
- [ ] Phase 6 — dashboards + alerts
- [ ] Phase 7 — demo flow + guide
- [ ] Phase 8 — teardown + GitHub push
