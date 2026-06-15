# Demo Flow — Robot Shop on EKS + AI Observability with New Relic

A tight, end-to-end click path for the live certification demo (~25–30 min).
Have these tabs open beforehand: **New Relic** (one.newrelic.com), the **robot-shop**
storefront URL, the **AI assistant** URL, and **PagerDuty**. A terminal on the EKS
context for the live `kubectl`/script moments. Run `scripts/verify.sh` an hour before
to confirm all signals are green.

---

## 0. Setup (before the audience joins)
- Cluster up, robot-shop + AI assistant deployed, loadgens running, dashboard + alerts + PagerDuty wired.
- `bash scripts/verify.sh` → all six signals **PASS**.
- `kubectl config current-context` → confirm it's the **EKS** arn, not `orbstack`.
- Open the dashboard permalink (from `deploy-dashboard.sh`) in a tab.
- **Account hygiene:** stop the old local `k8s-ai-newrelic-demo` (services `api`/`llm-gateway`/`retriever`)
  if OrbStack is running, or rely on the robot-shop service filters — otherwise those pollute NRQL.

## 1. Frame the story (1 min)
> "We're running a real microservices store — Instana's robot-shop — on Amazon EKS,
> plus an OpenAI-powered shop assistant. Everything you'll see in New Relic is live
> telemetry: Kubernetes, **OpenTelemetry** traces, logs, and full AI observability —
> with alerts that page PagerDuty. No screenshots."

## 2. Kubernetes & infrastructure (4 min)
1. New Relic → **Kubernetes** (cluster explorer) → select `robot-shop-eks`.
2. Show the cluster map: nodes → namespaces → pods. Click a robot-shop pod → live CPU/mem, restarts.
3. Open the **dashboard → Kubernetes page**: pods by deployment, node CPU, restarts, K8s events.
4. Talking point: "This is the `nri-bundle` — infra agent, kube-state-metrics, kube-events, all zero-code."

## 3. The application & distributed tracing (5 min)
1. Open the **robot-shop storefront**; browse a product, add to cart, check out (drives traffic).
2. New Relic → **APM & Services** → show the robot-shop services (cart, catalogue, user, shipping, payment).
3. Open one service → **Distributed tracing** → pick a trace → show the span waterfall across services + DB calls.
4. Dashboard → **Robot Shop APM & Traces page**: throughput, p95 latency, error rate, slow DB spans.
5. Talking point: "These traces come from OpenTelemetry auto-instrumentation injected by the OTel Operator — we didn't touch the app's source."

## 3b. Prove it's *real* OpenTelemetry (4 min) — see demo-guide.md § 4b
Run in a terminal: **`bash scripts/show-otel.sh`** and narrate the four beats:
1. **Declarative** — `kubectl get opentelemetrycollector,instrumentation -n observability` (tracing is K8s resources).
2. **Zero-touch injection** — the injected init-container + `OTEL_*` env on a cart pod (app image unchanged).
3. **Vendor-neutral collector** — OTLP in → `otlphttp/newrelic` out ("repoint one line at Jaeger/Tempo").
4. **Proof in NR** — spans tagged `instrumentation.provider=opentelemetry`, faceted by real OTel libraries
   (Node: express/http/mongodb/redis; Java: tomcat/hibernate/jdbc/spring-data).
5. Talking point: "Zero app changes, polyglot via one Operator, W3C `traceparent` propagation —
   and the gotchas we hit (Node-14 image, Java OOM + gRPC protocol) are real OTel-adoption lessons."

## 4. AI Observability — the headline (6 min)
1. Open the **AI assistant**; ask: *"What's a good starter drone?"* and *"Anything under $100?"*
2. New Relic → **AI Monitoring** → show:
   - The `robot-shop-ai-assistant` app, response view with **prompt + completion** captured.
   - **Token usage** and **model** (`gpt-4o-mini`), **response time**.
3. Click an OpenAI call → show it inside a **distributed trace** → the assistant → **catalogue** call.
4. Dashboard → **AI Monitoring page**: completions/min, tokens by model, estimated cost, p95 latency, recent prompts.
5. Talking point: "New Relic auto-instruments the OpenAI SDK — token cost, latency, and even the prompt/response content, correlated with the rest of the stack."

## 5. Logs in context (2 min)
1. From a pod in the cluster explorer → **See logs**, or Dashboard → **Logs page**.
2. Filter to error-level logs; show logs are correlated to the K8s entity.

## 5b. Synthetic monitoring — proactive, outside-in (2 min) — see demo-guide.md § 8
1. **Synthetic monitoring** → show the 3 monitors, all green:
   - **robot-shop storefront (browser)** — real Chrome from AWS ap-south-1 + us-east-1; open a
     result → **page-load waterfall + screenshot** of the actual storefront.
   - **ai-assistant health (ping)** — lightweight liveness on `/healthz`.
   - **ai-assistant chat e2e (api)** — a scripted monitor that **POSTs a real question to
     `/chat`** and asserts a non-empty answer — it exercises the whole OpenAI path from outside
     the cluster (and quietly keeps AI Monitoring fed).
2. **Say:** *"This is synthetic, outside-in monitoring — we catch problems from the user's
   vantage point before a real user does, from multiple regions. The scripted one actually
   talks to the AI every 5 minutes."* Failures feed the **same** alert policy → PagerDuty.

## 6. RCA / failure scenario → PagerDuty (5 min) — see demo-guide.md "Break it on purpose"
1. Trigger the failure: `kubectl scale deploy/catalogue --replicas=0 -n robot-shop`.
2. Watch the chain: error rate climbs (APM page) → New Relic **issue opens** → the
   `Robot Shop -> PagerDuty` workflow fires → **PagerDuty incident pages**.
3. Switch to **PagerDuty** → show the incident carrying the New Relic issue title + details.
4. Service map shows the broken dependency; **Logs** show connection-refused errors in the same window.
5. Restore: `kubectl scale deploy/catalogue --replicas=1 -n robot-shop` → error rate falls,
   the issue closes, and the **PagerDuty incident auto-resolves**.
   > Optional outside-in variant: `kubectl scale deploy/web --replicas=0 -n robot-shop` trips the
   > **storefront browser monitor** → "Synthetic monitor failure" condition pages. Restore with `--replicas=1`.

## 7. Wrap (1 min)
- Recap the surfaces — **one platform**: K8s + infra, APM & **OpenTelemetry** distributed tracing,
  AI Monitoring, logs, **synthetic monitoring**, NRQL alerts → **PagerDuty**.
- Everything is **as code** and version-controlled: dashboards (`deploy-dashboard.sh`),
  alerts (`alerts.sh`), PagerDuty routing (`pagerduty.sh`), and the OTel + K8s manifests.
- Mention `scripts/show-otel.sh` and `scripts/verify.sh` as the repeatable proof tools.
