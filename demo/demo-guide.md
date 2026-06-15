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
- **What:** `newrelic/alerts.sh` creates a policy + 6 NRQL conditions via NerdGraph;
  `newrelic/pagerduty.sh` adds a **Destination → Channel → Workflow** that pages PagerDuty
  on any of this policy's issues.
- **Conditions:** pod crashloop, pod not ready, service error rate >10%, API p95 >1.5s,
  **LLM hourly cost guard**, log error surge.
- **Say:** *"Conditions are NRQL, defined as code. Issues route through a Workflow to a
  PagerDuty service — so a threshold breach becomes a real incident on someone's phone.
  Including an **AI cost guard**: if OpenAI spend in an hour crosses a threshold, it pages —
  the kind of control AI apps need and rarely have."*
- **Flow to show:** Alerts & AI → **Workflows** (`Robot Shop -> PagerDuty`) → **Destinations**
  (the PagerDuty service). Then trigger the RCA below and switch to the PagerDuty incident view.

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
