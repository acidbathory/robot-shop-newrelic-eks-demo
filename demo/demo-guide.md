# Demo Guide — Rich Talking Points

Companion to `demo-flow.md`. For each New Relic surface: **what it is**, **why it matters**,
**what to say**, the **NRQL** to show, and the **"wow" moment**. Cluster name everywhere is
`robot-shop-eks`; account `8059020`.

---

## Architecture recap (say this once, up front)
> "Three things are running on EKS: (1) **robot-shop**, a 12-service polyglot store —
> Node.js, Java, Python, Go, PHP, with MongoDB, MySQL, Redis, and RabbitMQ; (2) an **OpenAI
> shop assistant** I built; and (3) the New Relic agents. Telemetry reaches New Relic two ways:
> the **nri-bundle** for Kubernetes, and an **OpenTelemetry collector** for traces and the
> assistant's AI data. One backend, one correlated view."

---

## 1. Kubernetes monitoring (nri-bundle)
- **What:** Infra agent + kube-state-metrics + kube-events + Fluent Bit, installed via one Helm chart.
- **Why it matters:** Cluster, node, pod, and container health without instrumenting anything. Ops teams live here.
- **Say:** *"This is the operational layer — is the cluster healthy, are pods scheduled, is anything restarting or OOMing? All zero-code, installed with one `helm upgrade`."*
- **NRQL:**
  - `SELECT uniqueCount(podName) FROM K8sPodSample WHERE clusterName='robot-shop-eks' FACET deploymentName`
  - `SELECT max(restartCount) FROM K8sContainerSample WHERE clusterName='robot-shop-eks' FACET podName`
- **Wow:** Cluster explorer's live map — click a node and drill straight to a pod's CPU/memory and its logs.

## 2. Kubernetes events
- **What:** `nri-kube-events` streams scheduling decisions, OOMKills, image-pull errors, evictions.
- **Why:** The "why did this pod move/die?" answer, in the same timeline as metrics.
- **Say:** *"When something changes in the cluster, the event is right next to the metric that moved."*
- **NRQL:** `SELECT reason, message FROM InfrastructureEvent WHERE clusterName='robot-shop-eks' SINCE 1 hour ago`

## 3. Logs (Fluent Bit) with correlation
- **What:** Every pod's stdout/stderr forwarded to New Relic Logs, tagged with K8s metadata.
- **Why:** Logs in context — jump from a pod or a trace to its logs without grep-ing kubectl.
- **Say:** *"Logs aren't a separate tool here — they're attached to the entity that produced them."*
- **NRQL:** `SELECT message, pod_name FROM Log WHERE cluster_name='robot-shop-eks' SINCE 30 minutes ago`
- **Wow:** From the cluster explorer, click a pod → **See logs** → instantly filtered to that pod.

## 4. APM + distributed tracing (OpenTelemetry)
- **What:** The OTel Operator injects auto-instrumentation into robot-shop's Java/Node/Python
  services; spans flow through our collector to New Relic.
- **Why:** See request flow across services, find the slow hop, see DB calls — the developer's view.
- **Say:** *"We added zero lines to robot-shop. The OTel Operator injects the agent at pod startup
  based on an annotation. New Relic builds the service map and traces from the spans."*
- **Honest coverage note:** *"Java, Node, and Python are auto-instrumented (shipping, cart, catalogue,
  user, payment). Go (dispatch) and PHP (ratings) aren't OTel-auto, so they show as downstream calls
  rather than first-class services — that's a real platform tradeoff worth calling out."*
- **NRQL:**
  - `SELECT percentile(duration.ms, 95) FROM Span WHERE span.kind='server' FACET service.name TIMESERIES`
  - `SELECT average(duration.ms), count(*) FROM Span WHERE span.kind='client' FACET service.name, name`
- **Wow:** A single trace waterfall spanning web → catalogue → MongoDB, with timings per hop.

## 4b. Showcasing OpenTelemetry *explicitly* (the "this is real OTel" proof)
Run **`bash scripts/show-otel.sh`** live, or walk these four beats. The point: **nothing about
the tracing is New Relic-specific or baked into the app** — it's the upstream OTel SDK,
configured declaratively, exporting standard OTLP.

1. **It's declarative — tracing is Kubernetes resources, not app code.**
   `kubectl get opentelemetrycollector,instrumentation -n observability`
   > *"Two custom resources define everything: a collector and an `Instrumentation` policy
   > (sampler, propagators, exporter endpoint). No tracing code in robot-shop."*

2. **Zero-touch injection — the Operator adds the OTel SDK at pod startup.**
   `kubectl get pod -n robot-shop -l service=cart -o yaml` → show the **init container**
   `opentelemetry-auto-instrumentation-nodejs` and the injected env:
   `NODE_OPTIONS=--require …/autoinstrumentation.js`, `OTEL_SERVICE_NAME`,
   `OTEL_EXPORTER_OTLP_ENDPOINT=…:4317`, `OTEL_PROPAGATORS=tracecontext,baggage,b3`.
   > *"The app image is unchanged. The Operator injected the upstream OTel SDK via a single
   > pod annotation — same mechanism for Node, Java, and Python."*

3. **The collector is the vendor-neutral hop — OTLP in, OTLP out.**
   Show `observability/otel-collector.yaml`: receivers `otlp` (4317/4318) → processors
   `k8sattributes`/`batch` → exporter **`otlphttp/newrelic`** (`https://otlp.nr-data.net`).
   > *"Standard OTLP arrives; the New Relic exporter is one block. Repoint that single
   > `endpoint` at Jaeger, Grafana Tempo, or any OTLP backend and the app never knows."*

4. **Proof in New Relic — spans are tagged as OpenTelemetry, by library.**
   - `SELECT count(*) FROM Span WHERE instrumentation.provider='opentelemetry' FACET service.name`
   - `SELECT count(*) FROM Span WHERE service.name IN ('catalogue','cart','user','shipping') FACET otel.library.name`
     → Node: `@opentelemetry/instrumentation-express`, `-http`, `-mongodb`, `-redis`;
       Java: `io.opentelemetry.tomcat-7.0`, `hibernate-4.0`, `jdbc`, `spring-data-1.8`.
   - `SELECT latest(telemetry.sdk.language), latest(telemetry.sdk.version) FROM Span FACET service.name`
   > *"Every span carries `instrumentation.provider = opentelemetry` and the exact OTel library
   > that produced it. This is the OTel SDK's own instrumentation, surfaced natively — and the
   > W3C `traceparent` header is why one trace stitches across services."*

**Two real-world OTel gotchas we hit (great honesty points):**
- robot-shop's Node services run **Node 14** → had to pin an older auto-instrumentation image
  (current needs Node 16+). *(see `observability/instrumentation.yaml`)*
- The **Java agent OOMKilled** at robot-shop's 1000Mi limit (JVM + agent), and defaults to OTLP
  **http/protobuf** which fails against our gRPC port → bumped memory + forced `OTEL_EXPORTER_OTLP_PROTOCOL=grpc`.

> **Demo-account hygiene:** the old local `k8s-ai-newrelic-demo` (services `api`, `llm-gateway`,
> `retriever`) also reports to this account when OrbStack is running. Filter NRQL by the
> robot-shop service names (as `show-otel.sh` does), or stop that local cluster before presenting.

## 5. AI Monitoring (OpenAI) — the headline
- **What:** The assistant runs under New Relic's **Python APM agent**, which auto-instruments the
  **OpenAI SDK**. Every chat completion becomes an AI Monitoring event with model, tokens, latency,
  and (optionally) the full prompt + response.
- **Why:** AI apps are black boxes without this — you can't see cost, latency, drift, or what the
  model actually said. New Relic makes LLM calls first-class telemetry.
- **Say:** *"This is the part teams struggle with. I didn't write any tracing code — I ran the app
  under `newrelic-admin` and flipped `ai_monitoring.enabled`. Now every OpenAI call shows token
  usage, cost, latency, the model, and the prompt/response — correlated with the trace that
  triggered it. When the assistant calls the catalogue service, that hop is in the same trace."*
- **NRQL:** (token counts live on `LlmChatCompletionMessage.token_count`; `is_response` splits output vs input)
  - `SELECT sum(token_count) FROM LlmChatCompletionMessage FACET response.model`
  - cost ≈ `SELECT filter(sum(token_count), WHERE is_response IS FALSE)/1e6*0.15 + filter(sum(token_count), WHERE is_response IS TRUE)/1e6*0.60 FROM LlmChatCompletionMessage` (gpt-4o-mini: $0.15/$0.60 per 1M in/out)
  - `SELECT content, role FROM LlmChatCompletionMessage SINCE 30 minutes ago`
- **Wow:** Ask the live assistant a question, then watch it appear in AI Monitoring seconds later —
  prompt, response, tokens, cost — inside a distributed trace that also shows the catalogue call.

## 6. Dashboards as code
- **What:** `newrelic/dashboard.json` deployed via NerdGraph (`dashboardCreate`). 4 pages.
- **Why:** Reproducible, version-controlled observability — no click-ops drift.
- **Say:** *"The whole dashboard is a JSON file in git. `deploy-dashboard.sh` creates it via the API
  and prints the permalink. Same for alerts."*

## 7. NRQL alerts → PagerDuty
- **What:** `newrelic/alerts.sh` creates a policy + 7 NRQL conditions via NerdGraph;
  `newrelic/pagerduty.sh` adds a **Destination → Channel → Workflow** that pages PagerDuty
  on any of this policy's issues.
- **Conditions:** pod crashloop, pod not ready, service error rate >10%, API p95 >1.5s,
  **LLM hourly cost guard**, log error surge, **synthetic monitor failure**.
- **Say:** *"Conditions are NRQL, defined as code. Issues route through a Workflow to a
  PagerDuty service — so a threshold breach becomes a real incident on someone's phone.
  Including an **AI cost guard**: if OpenAI spend in an hour crosses a threshold, it pages —
  the kind of control AI apps need and rarely have."*
- **Flow to show:** Alerts & AI → **Workflows** (`Robot Shop -> PagerDuty`) → **Destinations**
  (the PagerDuty service). Then trigger the RCA below and switch to the PagerDuty incident view.

## 8. Synthetic monitoring (proactive, outside-in)
- **What:** `newrelic/synthetics.sh` creates three monitors as code, run from AWS public
  locations **ap-south-1 + us-east-1** every 5 min:
  - **Browser** (`robot-shop storefront (browser)`) — a real headless Chrome loads the storefront;
    you get availability, **page-load timing**, and a **screenshot** per check.
  - **Ping** (`ai-assistant health (ping)`) — cheapest liveness check on `/healthz`.
  - **Scripted API** (`ai-assistant chat e2e (api)`) — a Node script **POSTs a real question to
    `/chat`** and asserts HTTP 200 + a non-empty `reply`. It validates the entire OpenAI round-trip
    from outside the cluster, and the steady traffic also keeps AI Monitoring populated.
- **Why it matters:** everything else in this demo is *inside-out* (the app emits telemetry).
  Synthetics is *outside-in* — it catches "the site is down / slow / the AI stopped answering"
  from the **user's vantage point and from multiple regions**, even at 3am with zero real traffic.
- **Say:** *"Two complementary angles: the app tells us how it feels from the inside, and
  synthetics tells us how it looks from the outside, worldwide. The scripted check literally asks
  the assistant a question every five minutes — if the model, the key, or the network breaks, we
  know before a customer does."*
- **Wired to PagerDuty:** the **"Synthetic monitor failure"** condition is in the same policy, so a
  failed check from any location pages through the same Workflow. Demo it by scaling `web` to 0
  (the browser monitor goes red → incident) — see the outside-in variant in the RCA below.
- **NRQL to show:** `SELECT count(*) FROM SyntheticCheck FACET monitorName, result SINCE 1 hour ago`
  and `SELECT average(duration) FROM SyntheticCheck WHERE monitorName LIKE '%storefront%' TIMESERIES`.

---

## Break it on purpose — the RCA money shot
The retriever-style failure story, done with robot-shop's catalogue:

```bash
# 1. Take catalogue down
kubectl scale deploy/catalogue --replicas=0 -n robot-shop
```
Then narrate, in New Relic, in this order (cause → effect → evidence → page):
1. **APM page** — catalogue error rate / dependent services' error rate climbs within ~1 min.
2. **Alerts** — the "Service error rate" condition opens an issue.
3. **PagerDuty** — the workflow forwards the issue; a **PagerDuty incident** is created and pages.
   Switch to the PagerDuty incident to show the New Relic issue title + details in the payload.
4. **Service map / distributed tracing** — the broken edge to catalogue is visible; traces error at that hop.
5. **Logs** — dependent pods show connection-refused / timeout messages, correlated to the same window.
6. **Restore:**
```bash
kubectl scale deploy/catalogue --replicas=1 -n robot-shop
```
   Watch error rate fall, the New Relic issue close, and the **PagerDuty incident auto-resolve**.
   *"Mean-time-to-resolution is short when cause, effect, evidence, and paging are in one place."*

> Alternative AI-flavored RCA: point the assistant's `CATALOGUE_URL` at a bad host (or scale catalogue
> to 0) and show the assistant degrade — its traces error on the catalogue hop while OpenAI calls
> still succeed, isolating the failure to the dependency, not the model.

---

## Likely questions (have answers ready)
- **"Why OTel for the app but agents for K8s/AI?"** — OTel gives vendor-neutral, zero-code tracing
  across a polyglot app; the NR APM agent gives the richest AI Monitoring (prompt/response capture).
  New Relic ingests both natively and correlates them.
- **"Does capturing prompts/responses leak data?"** — `ai_monitoring.record_content.enabled` is a
  toggle; turn it off to keep metadata (tokens/latency/model) without content.
- **"What does this cost to run?"** — EKS control plane + 3× t3.large ≈ $10–12/day in ap-south-1;
  OpenAI on gpt-4o-mini is cents at demo volume. Everything tears down with `scripts/teardown.sh`.
- **"Is the AI cost real or estimated?"** — token counts are real (from the API response); the USD
  figure is computed from published gpt-4o-mini pricing in NRQL.

---

## Competitive talking points (when asked)
> Source: `compete.md` (Competitive Intelligence battlecards). **Lead with structural and
> commercial arguments; validate specific feature claims before stating them live** — competitors'
> OTel and AI capabilities move fast (Datadog has shipped Bits AI GA and expanded OTel support;
> Grafana and Dynatrace ship constantly). Don't over-claim; acknowledge real strengths, then pivot.

**The one frame:** New Relic is a *genuinely* unified platform — one data store (NRDB), one query
language (NRQL), OTel-native ingest, consumption pricing. The competitors are either separately
metered products behind a unified UI (Datadog), a proprietary closed AI stack (Dynatrace), or a
set of open-source components you assemble and maintain yourself (Grafana). **This demo is the
proof** — point at it rather than asserting it.

### Map each demo moment → the competitive win theme
| In the demo you showed… | Use it to make this point | Against |
|---|---|---|
| §3b OTel showcase (init-container injection, OTLP in/out, `provider=opentelemetry`) | **OTel-native, no proprietary agent.** "Repoint one exporter line at any backend." | **Datadog** (historically needs its agent for full value); **Grafana Alloy** (a proprietary OTel fork = Grafana lock-in) |
| §2→§3→§5→§4 navigating K8s → traces → logs → AI in one UI, all NRQL | **One data model, one query language.** No PromQL-vs-log-search-vs-trace-explorer seams. | **Datadog** (loosely-coupled backends); **Grafana** (LGTM: Loki/Mimir/Tempo stitched at the UI) |
| §3 auto-generated service map | **Entity-centric, generated not configured.** No manual tag drift. | **Datadog** (manual tagging for service maps) |
| §4 / §4b AI Monitoring (tokens, cost, model, prompt/response, in-trace) | **Native LLM observability**, correlated with the rest of the stack. | **Dynatrace** (per battlecard: no native AI workload monitoring); Datadog/Grafana AI newer |
| §7 alerts → PagerDuty, all as code | **Open ecosystem.** Routes to your tools (PagerDuty, LaunchDarkly, ServiceNow) — no forced bundle. | **Dynatrace** DevCycle bolt-on; closed control plane |
| High-cardinality K8s + AI spans ingested with no pre-config | **Cardinality without ingestion controls** ("pay more or see less"). | **Datadog** cardinality ceilings |

### Datadog — lead with *unification-is-cosmetic* and *pricing unpredictability*
- **Unified UI ≠ unified data.** *"Their dashboard looks unified. During a P1, how many query
  languages and interfaces does your team actually touch moving from metric → log → trace? That seam
  is the architecture."*
- **Pricing is the most durable argument** (Gartner cost caution 3 years running). Multi-SKU, per-meter;
  the customer quote: *"I can estimate within 2x–5x of our actual bill."* Conditional deps (DB Monitoring
  requires Infra Monitoring); overage penalties. NR = consumption on data + users.
- **OTel:** *"The question isn't whether Datadog accepts OTel — it does. It's whether you need their
  agent alongside your collector for the full experience."* ⚠️ Verify current Datadog OTel state before specifics.
- **Acknowledge:** 800+ integrations, fast cloud onboarding, strong dev brand. Pivot breadth → depth.

### Dynatrace — lead with *cost/DPS complexity*, *closed AI*, and *no native AI-workload monitoring*
- **Closed vs open AI.** Dynatrace "Fusion AI" requires the full proprietary stack (Smartscape, Grail,
  OneAgent). *"Are you ready to give an autonomous agent write access to prod with no human in the loop?"*
- **AI workload gap (most relevant to our §4):** per the battlecard, Davis monitors infra/RCA but **not
  AI workloads themselves** — no token tracking, no per-model cost, no hallucination/drift detection.
  Our demo shows exactly that, natively. ⚠️ Verify current Dynatrace AI-monitoring state before specifics.
- **TCO/DPS:** RAM-based host pricing gets *more* expensive as you go cloud-native; DPS contracts flagged
  by Gartner 3 years running. Ask: *"What does your Year 2–3 DPS commit look like if consumption doubles?"*
- **Implementation:** OneAgent + OpenPipeline + Bindplane (two pipelines, not unified). *"15-week rollout vs a working POC by end of week one?"*
- **Acknowledge:** strong causal AI / Davis, deep enterprise footprint.

### Grafana — lead with *the management tax* and *open-source ≠ Grafana Cloud*
- **Assume it's already there.** The deal is usually *self-hosted LGTM vs Grafana Cloud vs New Relic as the managed alternative* — not greenfield.
- **Management tax.** *"Loki + Mimir + Tempo are separate components you assemble, scale, and maintain.
  How many engineer-hours/week go to running that stack?"* — that erodes the license savings.
- **"Open" rebuttal:** **Grafana Alloy is a proprietary OTel fork** → Grafana-specific lock-in. New Relic
  takes the native OTel collector. (Strong tie to §3b — we run upstream OTel, no fork.)
- **Composability caveat:** Grafana can *show* New Relic/Datadog/CloudWatch on one dashboard, but you
  can't *correlate, investigate, or get AI across it.* "Seeing ≠ resolving."
- **Acknowledge:** genuinely excellent dashboards, real community/standards cred, cloud-marketplace billing.
  Don't fight on dashboard aesthetics — pivot to *what happens after you see the dashboard* (RCA → resolution, our §6).

### Quick objection → pivot
| Prospect says… | Lead with… |
|---|---|
| "Datadog/Dynatrace is the market leader" | NR is a 13-yr Gartner Leader; Gartner cost/complexity cautions on the others |
| "They have a unified platform" | "Walk me through a P1 across your telemetry" — exposes the multi-store seam (show our single-UI flow) |
| "They're cheaper" | Total cost: list + commitment + overage + conditional deps; the Datadog 2x–5x forecasting quote |
| "They have AI now" | What does the AI *do in an incident*? Show native LLM tokens/cost + RCA→PagerDuty (§4, §6) |
| "We're already on Grafana" | Self-hosted vs Cloud vs managed; quantify the management tax; Alloy = a fork |
| "We like their dashboards" | Acknowledge; pivot to resolution speed — does the dashboard shorten MTTR? |
