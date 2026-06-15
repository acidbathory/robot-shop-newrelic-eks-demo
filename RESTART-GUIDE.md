# Restart Guide — bring this demo back up from scratch

A runbook any Claude instance (or human) can follow to rebuild the **robot-shop on EKS +
OpenAI AI-observability** demo and get all six New Relic signals green. Steps are ordered;
each has an approximate wall-clock time. **Total from nothing ≈ 50–65 min**, dominated by
EKS provisioning.

> Run everything from the repo root: `cd /Users/abal/Documents/Projects/demo-cert`

---

## 0. Prerequisites & secrets  (~1 min, or ~3 min if tools missing)

**Tools:** `aws` (configured, account `926634327293`), `kubectl`, `helm`, `docker` (OrbStack),
`eksctl`, `gh`, `jq`, `git`. Install the two that may be missing:
```bash
brew install eksctl gh        # ~2-3 min if not already present
```

**Secrets live in the macOS Keychain** (NOT in the repo). Required entries:
| Keychain service | What |
|---|---|
| `newrelic_user_api_key` | NRAK… — NerdGraph (dashboards/alerts/verify) |
| `newrelic_ingest_license_key` | NRAL — telemetry ingest |
| `openai_api_key` | sk-proj… — the shop-assistant |
| `github_pat` | push (needs **Contents: Read and write**) |

If any are missing, add them: `security add-generic-password -a "$USER" -s <service> -w "<value>" -U`

**Generate `.env` from the Keychain** (gitignored):
```bash
bash scripts/load-env.sh      # instant
```
Constants baked in: account `8059020`, region `ap-south-1`, cluster `robot-shop-eks`,
US datacenter (`otlp.nr-data.net`), `OPENAI_MODEL=gpt-4o-mini`.

---

## 1. Provision EKS  (~17–20 min ⏳ the long pole)
```bash
eksctl create cluster -f eks/cluster.yaml      # ~15-18 min (run in background)
aws eks update-kubeconfig --name robot-shop-eks --region ap-south-1
kubectl get nodes                              # expect 3x Ready, k8s 1.33
aws ecr create-repository --repository-name ai-assistant --region ap-south-1 || true
```
> `eks/create-cluster.sh` does all of the above idempotently. The cluster's default
> StorageClass is `gp2` (already matched in `robot-shop/values-eks.yaml`).

---

## 2. New Relic Kubernetes integration  (~2 min install, +3–5 min for data)
```bash
bash newrelic/install-nri-bundle.sh            # helm --wait ~1-2 min
```
K8s/infra/logs/events appear in New Relic ~3–5 min later.

---

## 3. Deploy robot-shop  (~5–8 min)
```bash
bash robot-shop/deploy.sh                       # helm --wait ~5 min + ELB ~2-3 min
```
Prints the storefront ELB URL. All 12 services + loadgen should be Running.

---

## 4. OTel tracing (operator + collector + auto-instrumentation)  (~8–12 min)
```bash
bash observability/install-operator.sh          # cert-manager + operator + collector ~5-7 min
bash observability/annotate-robotshop.sh         # rollouts ~3-5 min
```
> ⚠️ **Two gotchas already fixed in the repo — do NOT revert them:**
> - `observability/rbac.yaml` creates the `nr-collector` ServiceAccount (the operator
>   only auto-creates a SA when none is named). Without it the collector won't schedule.
> - `observability/instrumentation.yaml` pins `autoinstrumentation-nodejs:0.46.0` because
>   robot-shop's Node services run **Node 14** (the default image needs Node 16+ and
>   crashloops with `performance is not defined`).
> - `observability/instrumentation.yaml` sets `java.env OTEL_EXPORTER_OTLP_PROTOCOL=grpc`
>   (the Java agent defaults to http/protobuf, which fails against the collector's gRPC :4317).
> - `robot-shop/helm/templates/shipping-deployment.yaml` memory is **1536Mi** (was 1000Mi);
>   the JVM + OTel Java agent OOMKilled at 1000Mi. (Both baked in — no manual step.)
>
> Verify all 3 languages trace after a few min of traffic:
> `bash scripts/show-otel.sh`  (Node + Java spans; payment/Python needs checkout traffic)
>
> If the collector deploy hangs in `FailedCreate` backoff after the SA exists, nudge it:
> `kubectl delete rs -n observability -l app.kubernetes.io/name=nr-collector`

Coverage note: Java (shipping), Node (cart/catalogue/user), Python (payment) are
auto-instrumented. Go (dispatch) and PHP (ratings) are not — expected.

---

## 5. OpenAI shop-assistant + AI Monitoring  (~6–10 min)
> 🚨 **CRITICAL — kubectl context.** Launching/using OrbStack for Docker **silently switches
> your kubectl context to `orbstack` (local)**. Before any deploy, confirm you're on EKS:
> ```bash
> docker info >/dev/null 2>&1 || open -a OrbStack    # start Docker if down (~10s)
> kubectl config use-context arn:aws:eks:ap-south-1:926634327293:cluster/robot-shop-eks
> kubectl config current-context                      # MUST be the EKS arn, not "orbstack"
> ```
> If you skip this, the assistant deploys to the local cluster and `ImagePullBackOff`s on ECR.

```bash
bash ai-assistant/build-and-push.sh              # docker buildx linux/amd64 -> ECR ~3-5 min
# (re-assert EKS context here — build touched Docker)
kubectl config use-context arn:aws:eks:ap-south-1:926634327293:cluster/robot-shop-eks
bash ai-assistant/deploy.sh                      # secrets + deploy + ELB ~3-5 min
```
The assistant ELB URL is printed. The chat-loadgen starts immediately → **OpenAI billing
begins here** (pennies/day on gpt-4o-mini).

---

## 6. Dashboards & alerts as code  (~1 min)
```bash
bash newrelic/deploy-dashboard.sh                # prints dashboard GUID/permalink
bash newrelic/alerts.sh                          # policy + 7 NRQL conditions (incl. synthetic-failure)
bash newrelic/synthetics.sh                      # 3 synthetic monitors (browser + ping + scripted /chat)
# Optional — route alerts to PagerDuty (needs pagerduty_integration_key in Keychain):
bash newrelic/pagerduty.sh                       # destination + channel + workflow ~30s
```
> `synthetics.sh` reads the live ELB hostnames from the cluster, so run it AFTER the
> storefront + ai-assistant services have their LoadBalancers (Phases 3 & 5). Monitors run
> from AWS public locations (ap-south-1 + us-east-1) every 5 min; first results land ~5-10 min later.
> Both scripts **create new resources each run** (no upsert). Re-running makes duplicates —
> delete the old dashboard (`dashboardDelete`) / policy (`alertsPolicyDelete`) first if rerunning.
> `alerts.sh` already sets `set +o braceexpand` (GraphQL `{..,..}` would otherwise be mangled by bash).

---

## 7. Verify  (~1 min, after ~3–5 min of traffic)
```bash
bash scripts/verify.sh        # all 7 signals should PASS
```
Expected: K8s pods, Pod logs, APM/trace spans, AI completions, AI tokens, K8s events,
Synthetic checks — all PASS. (Synthetic checks lag ~5-10 min after `synthetics.sh`.)
> AI token counts live on `LlmChatCompletionMessage.token_count` (split by `is_response`),
> **not** on `LlmChatCompletionSummary`. Dashboard/alerts/verify already use the correct schema.

---

## Fast path A: cluster PAUSED (nodegroup scaled to 0)  (~8–10 min)
This is the usual state between rehearsals — `scripts/pause.sh` scaled `ng-robotshop` to 0
to cut EC2 cost while keeping the control plane, manifests, secrets, ELB URLs, and all NR
config. **Do NOT use the reconnect path below — it won't bring nodes back.** Resume with:
```bash
bash scripts/resume.sh        # scales nodegroup 0->3, fixes context, waits for rollouts
# then, after ~3-5 min of traffic:
bash scripts/verify.sh
```
> `resume.sh` re-asserts the EKS context (dodges the OrbStack trap), **re-enables the synthetic
> monitors**, and prints both ELB URLs.
> To pause again after rehearsal: `bash scripts/pause.sh` (residual ~$3–4/day while paused).
> `pause.sh` **disables the synthetic monitors first** — otherwise they'd fail against the
> down endpoints every 5 min and page PagerDuty for the whole pause. (`newrelic/toggle-synthetics.sh`
> handles both directions, finding monitors by tag so it survives rebuilds.)

## Fast path B: cluster up with nodes Ready (just reconnect)  (~1 min)
```bash
aws eks update-kubeconfig --name robot-shop-eks --region ap-south-1
kubectl config use-context arn:aws:eks:ap-south-1:926634327293:cluster/robot-shop-eks
bash scripts/load-env.sh && bash scripts/verify.sh
```

## Teardown (stop all AWS billing ~$11–13/day)  (~10–15 min)
```bash
bash scripts/teardown.sh      # deletes workloads, ELBs, cluster, ECR (guarded prompts)
```
> Delete LoadBalancer services before `eksctl delete cluster` (the script does this) so the
> ELBs are released and don't orphan. New Relic dashboards/alerts persist — remove in UI if desired.

---

## Time budget summary
| Step | Approx |
|---|---|
| 0. Prereqs + env | 1–3 min |
| 1. EKS provision | **17–20 min** |
| 2. nri-bundle | 2 min (+3–5 min data) |
| 3. robot-shop | 5–8 min |
| 4. OTel tracing | 8–12 min |
| 5. OpenAI assistant | 6–10 min |
| 6. Dashboards + alerts (+ PagerDuty) | 1–2 min |
| 7. Verify | 1 min (after data lands) |
| **Total (from scratch)** | **≈ 50–65 min** |
| Resume from paused (nodegroup 0→3) | 8–10 min |
| Reconnect (cluster up, nodes Ready) | ~1 min |
| Teardown | 10–15 min |
