# New Relic Demo Certification — EKS · robot-shop · AI Observability

A full-stack New Relic showcase built for a demo certification. It runs the
[Instana **robot-shop**](https://github.com/instana/robot-shop) polyglot microservices app on
**Amazon EKS**, adds an **OpenAI-powered shop-assistant chatbot**, and lights up New Relic
across **Kubernetes, APM, distributed tracing, logs, and AI Monitoring** — with
dashboards and alerts defined as code.

```
 EKS (ap-south-1)
  ├─ robot-shop      web · catalogue · cart · user · shipping · payment · ratings ·
  │                  dispatch · mongodb · mysql · redis · rabbitmq · loadgen
  │                    └─ OTel auto-instrumentation (java / node / python)
  ├─ ai-assistant    OpenAI shop-assistant (FastAPI + openai SDK + NR Python APM agent)
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
| 5 | AI Monitoring (tokens, cost, model, response) | OpenAI shop-assistant via NR Python APM agent |
| 6 | Dashboards as code | NerdGraph (`newrelic/dashboard.json`) |
| 7 | NRQL alerts → PagerDuty | NerdGraph (`newrelic/alerts.sh` + `newrelic/pagerduty.sh`) |
| 8 | Synthetic monitoring (browser, ping, scripted API) | NerdGraph (`newrelic/synthetics.sh`) |

## Layout
```
eks/            eksctl ClusterConfig + provisioning scripts
newrelic/       nri-bundle values/install, dashboard.json, alerts, deploy scripts
robot-shop/     vendored upstream Helm chart + values
observability/  OTel Operator install, collector config, Instrumentation CRD
ai-assistant/   OpenAI shop-assistant service (FastAPI), Dockerfile, k8s manifests, loadgen
demo/           demo-flow.md, demo-guide.md
scripts/        load-env, verify, show-otel, pause/resume, teardown helpers
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

## Pause / resume (cut cost between rehearsals)
```bash
bash scripts/pause.sh             # disable synthetics + scale nodegroup 3->0; keeps cluster, ELBs, NR config (~$3-4/day)
bash scripts/resume.sh            # scale 0->3, fix kubectl context, wait rollouts, re-enable synthetics (~8-10 min)
```
> `pause.sh` disables the synthetic monitors first so they don't page PagerDuty against the
> down endpoints; `resume.sh` re-enables them. (`newrelic/toggle-synthetics.sh ENABLED|DISABLED`.)

## Teardown
```bash
bash scripts/teardown.sh          # eksctl delete cluster + helm uninstalls + cleanup
```

> ⚠️ Cost: EKS control plane + 3× t3.large ≈ $10–12/day in ap-south-1. `pause.sh` drops this
> to ~$3–4/day without destroying anything; `teardown.sh` takes it to $0.

## Build status — complete & verified (all 7 NR signals green); currently paused
- [x] Phase 0 — repo + tooling bootstrap
- [x] Phase 1 — EKS cluster
- [x] Phase 2 — nri-bundle
- [x] Phase 3 — robot-shop
- [x] Phase 4 — OTel tracing (Node + Java + Python auto-instrumentation)
- [x] Phase 5 — OpenAI shop-assistant + AI Monitoring
- [x] Phase 6 — dashboards + alerts → PagerDuty
- [x] Phase 7 — demo flow + guide (+ competitive talking points)
- [x] Phase 8 — teardown + GitHub push
