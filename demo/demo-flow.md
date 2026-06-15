# Demo Flow — Robot Shop on EKS + Claude AI Observability with New Relic

A tight, end-to-end click path for the live certification demo (~20–25 min).
Have these tabs open beforehand: **New Relic** (one.newrelic.com), the **robot-shop**
storefront URL, and the **AI assistant** URL. Run `scripts/verify.sh` an hour before
to confirm all signals are green.

---

## 0. Setup (before the audience joins)
- Cluster is up, robot-shop + AI assistant deployed, loadgens running, dashboard created.
- `bash scripts/verify.sh` → all six signals **PASS**.
- Open the dashboard permalink (from `deploy-dashboard.sh`) in a tab.

## 1. Frame the story (1 min)
> "We're running a real microservices store — Instana's robot-shop — on Amazon EKS,
> plus a Claude-powered shop assistant. Everything you'll see in New Relic is live
> telemetry: Kubernetes, traces, logs, and full AI observability. No screenshots."

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

## 4. AI Observability — the headline (6 min)
1. Open the **AI assistant**; ask: *"What's a good starter drone?"* and *"Anything under $100?"*
2. New Relic → **AI Monitoring** → show:
   - The `robot-shop-ai-assistant` app, response view with **prompt + completion** captured.
   - **Token usage** and **model** (`claude-haiku-4-5`), **response time**.
3. Click a Claude call → show it inside a **distributed trace** → the assistant → **catalogue** call.
4. Dashboard → **AI Monitoring page**: completions/min, tokens by model, estimated cost, p95 latency, recent prompts.
5. Talking point: "New Relic auto-instruments the Anthropic SDK — token cost, latency, and even the prompt/response content, correlated with the rest of the stack."

## 5. Logs in context (2 min)
1. From a pod in the cluster explorer → **See logs**, or Dashboard → **Logs page**.
2. Filter to error-level logs; show logs are correlated to the K8s entity.

## 6. RCA / failure scenario (4 min) — see demo-guide.md "Break it on purpose"
1. Trigger the failure (`kubectl scale deploy/catalogue --replicas=0 -n robot-shop`).
2. Watch: error rate climbs (APM page) → alert opens → service map shows the broken dependency → logs show connection errors.
3. Restore (`kubectl scale deploy/catalogue --replicas=1 -n robot-shop`); show recovery.

## 7. Wrap (1 min)
- Recap the seven surfaces: K8s, infra, APM, distributed tracing, AI Monitoring, logs, alerts — one platform.
- Mention dashboards & alerts are **defined as code** (NerdGraph) and version-controlled in this repo.
