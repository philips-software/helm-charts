# k8s-observability-monitoring

![Version: 1.3.0](https://img.shields.io/badge/Version-1.3.0-informational?style=flat-square) ![AppVersion: 4.1.6](https://img.shields.io/badge/AppVersion-4.1.6-informational?style=flat-square)

Helm chart for k8s-observability-monitoring

## v1.0.0 Breaking Changes

This chart now wraps [k8s-monitoring v4.x](https://github.com/grafana/k8s-monitoring-helm) which has significant changes:

### Destinations Format

**Before (v3.x):**
```yaml
otlp:
  destinations:
    - name: "otlpGateway"
      url: "https://otlp-gateway.example.com/otlp"
      secret:
        name: "otlp-gateway-creds"
```

**After (v4.x):**
```yaml
destinations:
  otlpGateway:
    type: otlp
    url: "https://otlp-gateway.example.com/otlp"
    protocol: http
    auth:
      type: basic
      usernameKey: "username"
      passwordKey: "apiKey"
    secret:
      create: false
      name: "otlp-gateway-creds"
    metrics:
      enabled: true
    logs:
      enabled: true
    traces:
      enabled: true
```

### Features Format

**Before:**
```yaml
features:
  prometheusOperatorObjects: true
  clusterMetrics: false
```

**After:**
```yaml
prometheusOperatorObjects:
  enabled: true
clusterMetrics:
  enabled: false
```

### Pod Logs

Renamed from `podLogs` to `podLogsViaLoki`:
```yaml
podLogsViaLoki:
  enabled: true
  dropKubeProbe: true
  excludeNamespaces: []
```

## Installing on clusters with kube-prometheus-stack (KPS)

If your cluster already has [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) installed, you need additional configuration to avoid duplicate metrics.

### The Problem

When using k8s-monitoring alongside kube-prometheus-stack, you may encounter duplicate kube-state-metrics with corrupted job labels like:
- `crossplane-system/integrations/kubernetes/kube-state-metrics`
- `cert-manager/integrations/kubernetes/kube-state-metrics`

**Root cause:** the upstream k8s-monitoring chart converts scraped Prometheus
metrics to OTLP and back again. When kube-state-metrics is scraped this way,
each metric carries a `namespace` label for the resource it describes. If that
label is promoted to the `service.namespace` resource attribute, the namespace
prefix is injected into the `job` label **after** the `prometheus.relabel`
stage, inside the OTEL pipeline — producing the corrupted, per-namespace job
names above (and duplicate scrape jobs). This only manifests when KPS coexists,
because its kube-state-metrics ServiceMonitor is what the upstream collector
picks up.

> **Note:** earlier revisions of this chart blamed Alloy *clustering* for the
> prefix. That was a misdiagnosis — clustering is fine. The real trigger is the
> `service.namespace` attribute promotion in the OTLP round-trip, which is why
> `customAlloy.attributePromotion.enabled: false` is the actual fix.

**Confirmed present in the latest v4.** Rendering upstream `k8s-monitoring`
`4.1.6` (latest v4 release) with `clusterMetrics` + an OTLP destination still
generates the offending statement in the shared transform processor:

```alloy
otelcol.processor.transform "<destination>" {
  metric_statements {
    context = "datapoint"
    statements = [
      `set(resource.attributes["service.namespace"], attributes["service_namespace"] ) where ...`,
      ...
```

This promotion comes from the OTLP destination default
`processors.transform.metrics.datapointToResource: { service_namespace: service.namespace }`
(`destinations/otlp-values.yaml`). It is **on by default and not gated by any
feature flag** — the only way to suppress it upstream is to override that map
per-destination. customAlloy avoids the whole prometheus→OTLP→prometheus
round-trip, which is why it remains the cleaner fix. Verified identical from
`4.1.3` (our current pin) through `4.1.6`; no changelog entry in `4.1.4`–`4.1.6`
addresses it.

### The Solution

Enable `customAlloy` which deploys a dedicated Alloy instance for kube-state-metrics scraping without the problematic features:

```yaml
# values.yaml for clusters with KPS
customAlloy:
  enabled: true
  attributePromotion:
    enabled: false  # The actual fix: avoids the service.namespace promotion that corrupts job labels

# kube-state-metrics exclusion is automatically added when customAlloy.enabled: true
```

This configuration:
1. Deploys a dedicated Alloy instance that scrapes kube-state-metrics directly with correct job labels
2. Automatically excludes the kube-state-metrics ServiceMonitor from `prometheusOperatorObjects` to avoid duplicates

### When can customAlloy be removed?

`customAlloy` is a workaround, not a permanent feature. The removal trigger is
the **behaviour**, not any tracking issue: it can be removed once a future
k8s-monitoring release stops promoting `service_namespace → service.namespace`
in the metrics pipeline by default (or gates it behind a flag we can disable).
Migrating to v4 did **not** achieve this — the promotion is still emitted
unconditionally as of upstream `v4.1.6`.

To re-check after any upstream bump, render the chart and look for the
statement — if it's gone (or disableable), customAlloy can go too:

```bash
helm template t grafana/k8s-monitoring --version <new-version> -f - <<'EOF' | grep 'service.namespace'
cluster: {name: t}
destinations: {gw: {type: otlp, url: http://gw/otlp, protocol: http, auth: {type: none}}}
collectors: {alloy-metrics: {enabled: true, presets: [clustered]}}
clusterMetrics: {enabled: true, kube-state-metrics: {labelMatchers: {app.kubernetes.io/name: kube-state-metrics}}}
EOF
```

Then on a live KPS cluster, verify kube-state-metrics job labels are not
namespace-prefixed — `count by (job) (kube_pod_info)` should show a single,
clean `integrations/kubernetes/kube-state-metrics` job.

### OTLP Secret Requirements

The OTLP destination secret must contain these keys:
- `username`: Basic auth username
- `apiKey`: Basic auth password/token
- `tenantId`: The X-Scope-OrgID header value (e.g., `anonymous`)

```bash
kubectl create secret generic otlp-gateway-creds \
  --from-literal=username=otlp \
  --from-literal=apiKey=<your-token> \
  --from-literal=tenantId=anonymous
```

## Installing on clusters with Kyverno

If your cluster has [Kyverno](https://kyverno.io/) enforcing Pod Security Standards (baseline profile), Alloy pods may be blocked due to:
- `NET_RAW` capability requirement
- `hostPath` volumes for log collection (`/var/log`, `/var/lib/docker/containers`)

### Enable Kyverno PolicyException

Enable the built-in PolicyException to allow Alloy pods:

```yaml
kyverno:
  policyException:
    enabled: true
    policyName: "enforce-baseline-pod-security-profile"  # Your policy name
    ruleNames:
      - "enforce-baseline-profile"  # Rules to exempt
```

This creates a `PolicyException` resource that allows `k8s-monitoring-alloy-*` pods in the release namespace to bypass the specified policy rules.

## Capturing Cilium Hubble flow logs (L7 / access logs)

This chart can collect [Cilium Hubble](https://docs.cilium.io/en/stable/observability/hubble/) L7 flow records (HTTP/DNS/Kafka access logs) and ship them to a destination as logs. End-to-end this has **two halves** — one you configure on the Cilium side, one this chart provides:

```
Cilium agent  ──(static flow exporter)──▶  /var/run/cilium/hubble/events.log  (per node)
                                                      │
                                  (this chart: hubbleFlowLogs.enabled)
                                                      ▼
   alloy-logs DaemonSet  ──tail──▶  parse JSON ──▶ OTLP ──▶ your logs destination
```

### Why this is needed

Hubble flow records live in the cilium-agent's in-memory ring buffer and are exposed over the Hubble API / a Unix domain socket — they are **never written to pod stdout**. So ordinary pod-log collection (`podLogsViaLoki`) never sees them. To get them into your logging backend you must (1) have Cilium write them to a file on each node, and (2) tail that file. This chart does (2); you must do (1).

> **L7 flows require L7 visibility.** `event_type` 129 (AccessLog) records are only produced for traffic that Cilium's Envoy proxy actually parses — i.e. Gateway API / Ingress traffic, or pod traffic selected by a `CiliumNetworkPolicy` / `CiliumClusterwideNetworkPolicy` with L7 (`http:`) rules. Without any L7 policy, you will only see access logs for proxied (e.g. ingress) traffic. This chart does not configure L7 policies.

### Step 1 — Cilium side (prerequisite, configured in your Cilium release)

Enable Hubble's **static flow exporter** so each agent writes flow records to a host file. With the upstream Cilium Helm chart:

```yaml
# cilium values.yaml
hubble:
  enabled: true
  export:
    static:
      enabled: true
      filePath: /var/run/cilium/hubble/events.log
      # event_type 129 = AccessLog (L7/HTTP). Filtering to L7 only keeps the file small;
      # an unfiltered export captures every L3/L4 flow on every node (very high volume).
      allowList:
        - '{"event_type":[{"type":129}]}'
      # Native rotation keeps disk/RAM bounded (the default path is tmpfs-backed).
      fileMaxSizeMb: 50
      fileMaxBackups: 5
      fileCompress: true
```

Notes:
- `filePath` defaults here to `/var/run/cilium/hubble/events.log` (tmpfs/RAM-backed, already mounted into the agent). Records are ephemeral (lost on reboot), which is fine because the collector ships them off-node promptly. If you need persistence before collection, point it at a disk-backed host path instead and mount it accordingly.
- To capture **all** flows (L3/L4 + L7), drop the `allowList` — but expect a large volume.
- Verify Cilium is writing the file:
  ```bash
  kubectl exec -n kube-system <cilium-agent-pod> -c cilium-agent -- \
    tail -n 3 /var/run/cilium/hubble/events.log
  # expect JSONL records with "Type":"L7" and an l7.http object (method/url/code)
  ```

### Step 2 — this chart (collection)

Enable `hubbleFlowLogs`. It folds a self-contained flow-tail sub-pipeline into the `alloy-logs`
DaemonSet (a read-only `hostPath` mount of the export dir + tail → parse JSON → OTLP → your
destination), so no extra workload is created.

```yaml
hubbleFlowLogs:
  enabled: true
  # exportFilePath must match the Cilium hubble.export.static.filePath above.
  exportFilePath: /var/run/cilium/hubble/events.log
  # Destinations to ship flows to. Empty = reuse podLogsViaLoki's destinations
  # (or, if those are also empty, every destination with logs.enabled: true).
  destinations: []
  # Flow JSON is large (~4.5 KB/record). Keep OTLP batches under the gateway's gRPC
  # receive limit (commonly 4 MB) — 512 records ≈ 2.3 MB.
  batchMaxSize: 512
```

Flows are written to the destination with a fixed identity so they form a predictable stream
(in Loki: `{service_name="hubble-flows", service_namespace="cilium"}`), with `verdict`,
`flow_type`, `src_ns` and `dst_ns` promoted to structured metadata.

#### SPIFFE destinations

If a target destination uses SPIFFE (`auth.type: bearerToken` with a `bearerTokenFile`), the
`alloy-logs` DaemonSet needs the `spiffe-helper` sidecar to mint the token — add it to
`spiffe.collectors`, otherwise the chart fails the render with an explanatory message:

```yaml
spiffe:
  enabled: true
  collectors:
    - alloy-logs   # required for hubbleFlowLogs on a SPIFFE destination
```

### Verify end-to-end

```bash
# 1. The operator-GENERATED config actually contains the pipeline (not just the rendered values):
kubectl get cm <release>-alloy-logs -n <namespace> \
  -o jsonpath='{.data.config\.alloy}' | grep -c 'local.file_match "hubble"'   # expect 1

# 2. The DaemonSet is reading the file and exporting without failures:
kubectl port-forward -n <namespace> ds/<release>-alloy-logs 12345:12345 &
curl -s localhost:12345/metrics | \
  grep -E 'loki_source_file_read_lines_total.*events.log|otelcol_exporter_send_failed_log_records_total'

# 3. Flows arrive at the destination (Loki example):
#    {service_name="hubble-flows"}
```

(The default release name makes the collector `k8s-monitoring-alloy-logs`.)

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| applicationObservability | object | `{"destinations":[],"enabled":false,"receivers":{"otlp":{"grpc":{"enabled":true,"port":4317},"http":{"enabled":true,"port":4318}}}}` | Application observability (OTLP receiver for traces, metrics, logs from apps) |
| autoInstrumentation | object | `{"destinations":[],"enabled":false}` | Auto-instrumentation for applications |
| chart | object | `{"version":""}` | Override the upstream chart version (defaults to appVersion in Chart.yaml) |
| clusterMetrics | object | `{"destinations":[],"enabled":false,"kubelet":{"enabled":true,"metricsTuning":{"useDefaultAllowList":true},"nodeAddressFormat":"direct"},"kubeletResource":{"enabled":true,"nodeAddressFormat":"direct"}}` | Cluster metrics (kubelet, cadvisor) Note: kube-state-metrics is handled by customAlloy when enabled. |
| clusterName | string | `""` | Cluster name for telemetry labeling. Must be set to a non-empty value at install time. |
| collectorCommon | object | `{"alloy":{"controller":{"affinity":{"nodeAffinity":{"requiredDuringSchedulingIgnoredDuringExecution":{"nodeSelectorTerms":[{"matchExpressions":[{"key":"eks.amazonaws.com/compute-type","operator":"NotIn","values":["fargate"]}]}]}}}},"resources":{"limits":{"memory":"512Mi"},"requests":{"cpu":"100m","memory":"256Mi"}}}}` | Common collector settings (applies to all Alloy instances managed by operator) |
| collectorCommon.alloy.controller | object | `{"affinity":{"nodeAffinity":{"requiredDuringSchedulingIgnoredDuringExecution":{"nodeSelectorTerms":[{"matchExpressions":[{"key":"eks.amazonaws.com/compute-type","operator":"NotIn","values":["fargate"]}]}]}}}}` | Controller settings for pod scheduling |
| collectorCommon.alloy.controller.affinity | object | `{"nodeAffinity":{"requiredDuringSchedulingIgnoredDuringExecution":{"nodeSelectorTerms":[{"matchExpressions":[{"key":"eks.amazonaws.com/compute-type","operator":"NotIn","values":["fargate"]}]}]}}}` | Node affinity to prevent DaemonSets from scheduling on Fargate nodes. Fargate doesn't support DaemonSets, so we exclude nodes with eks.amazonaws.com/compute-type=fargate. |
| collectors | object | `{"alloy-logs":{"alloy":{"resources":{"limits":{"memory":"512Mi"},"requests":{"cpu":"100m","memory":"256Mi"}}}}}` | Per-collector settings (overrides collectorCommon for specific collectors) Available collectors: alloy-logs, alloy-metrics, alloy-receiver |
| customAlloy | object | `{"attributeCleanup":{"enabled":true},"attributePromotion":{"enabled":false},"clustering":{"enabled":false},"enabled":false,"kubeStateMetrics":{"extraMetricProcessingRules":""},"kubelet":{"enabled":false},"liveDebugging":{"enabled":true},"nodeExporter":{"extraMetricProcessingRules":""},"replaceUpstreamCollector":false,"replicas":1,"resources":{"limits":{"memory":"1Gi"},"requests":{"cpu":"100m","memory":"512Mi"}},"sendingQueue":{"enabled":true,"numConsumers":10,"queueSize":500},"vpa":{"enabled":false,"maxAllowed":{"memory":"8Gi"},"minAllowed":{"memory":"512Mi"},"updateMode":"InPlaceOrRecreate"}}` | Custom Alloy deployment for kube-state-metrics scraping Deploys separate Alloy instance with OTEL pipeline for metrics. This is preserved from v3.x to maintain the workaround for duplicate job labels. |
| customAlloy.replaceUpstreamCollector | bool | `false` | Replace upstream alloy-metrics collector entirely. |
| destinations | object | `{}` | OTLP destinations where telemetry data will be sent. Each destination is a map entry with the destination name as key. See: https://github.com/grafana/k8s-monitoring-helm/blob/main/charts/k8s-monitoring/docs/destinations/README.md  Set customAlloyOnly: true to exclude a destination from the upstream k8s-monitoring chart (it will only be used by customAlloy).  Example:   destinations:     otlpGateway:       type: otlp       url: "https://otlp-gateway.example.com/otlp"       protocol: http       auth:         type: basic         usernameKey: "username"         passwordKey: "apiKey"       secret:         create: false         name: "otlp-gateway-creds"       metrics:         enabled: true       logs:         enabled: true       traces:         enabled: true       processors:         batch:           enabled: true           size: 2000       sendingQueue:         enabled: true         queueSize: 100 |
| hubbleFlowLogs | object | `{"batchMaxSize":512,"destinations":[],"enabled":false,"exportFilePath":"/var/run/cilium/hubble/events.log"}` | Cilium Hubble L7 flow/access logs collection. Tails Cilium's flow export file on each node (via the alloy-logs DaemonSet) and ships it to a destination as OTLP logs. The chart does NOT configure Cilium: the operator must enable hubble.export on the Cilium side (file path below + allowlist event_type 129). Requires alloy-logs to have SPIFFE auth if a target destination uses bearerToken auth: add "alloy-logs" to spiffe.collectors. |
| hubbleFlowLogs.batchMaxSize | int | `512` | Max OTLP batch size for flows. Hubble flow JSON is large (~4.5 KB/flow); keep batches under the gateway's gRPC receive limit (commonly 4 MB). 512 ~= 2.3 MB. |
| hubbleFlowLogs.destinations | list | `[]` | Destinations to ship flows to. Empty = reuse the destinations resolved for podLogsViaLoki. |
| hubbleFlowLogs.exportFilePath | string | `"/var/run/cilium/hubble/events.log"` | Cilium hubble-export-file-path. The chart mounts this file's parent dir read-only. |
| kyverno | object | `{"policyException":{"enabled":false,"policyName":"enforce-baseline-pod-security-profile","ruleNames":["enforce-baseline-profile"]}}` | Kyverno PolicyException configuration |
| podLogsViaLoki | object | `{"destinations":[],"dropKubeProbe":false,"enabled":true,"excludeNamespaces":[]}` | Pod logs collection via Loki format |
| podLogsViaLoki.dropKubeProbe | bool | `false` | Drop kube-probe logs (liveness/readiness probe requests). |
| podLogsViaLoki.excludeNamespaces | list | `[]` | Namespaces to exclude from log collection. |
| project | object | `{"name":"default"}` | ArgoCD project name for the k8s-monitoring Application |
| prometheusOperatorObjects | object | `{"destinations":[],"enabled":true,"serviceMonitors":{"extraDiscoveryRules":"","extraMetricProcessingRules":"","labelExpressions":[],"metricsTuning":{"excludeMetrics":[]}}}` | Prometheus Operator Objects (ServiceMonitors, PodMonitors, Probes) |
| prometheusOperatorObjects.destinations | list | `[]` | Destinations to send metrics. Empty = all metrics-capable destinations. |
| prometheusOperatorObjects.serviceMonitors.extraDiscoveryRules | string | `""` | Extra discovery rules for ServiceMonitors (Alloy relabel config syntax). |
| prometheusOperatorObjects.serviceMonitors.extraMetricProcessingRules | string | `""` | Extra metric processing rules (Alloy relabel config syntax). |
| prometheusOperatorObjects.serviceMonitors.labelExpressions | list | `[]` | Label expressions to filter which ServiceMonitors to scrape. |
| prometheusOperatorObjects.serviceMonitors.metricsTuning | object | `{"excludeMetrics":[]}` | Metrics tuning to filter metrics. |
| prometheusOperatorObjects.serviceMonitors.metricsTuning.excludeMetrics | list | `[]` | Metrics to exclude. Can use regular expressions. Example: ["apiserver_request_duration_seconds_bucket"] |
| spiffe | object | `{"audience":"","collectors":[],"enabled":false,"helper":{"image":"ghcr.io/spiffe/spiffe-helper:0.10.0","resources":{"limits":{"memory":"32Mi"},"requests":{"cpu":"1m","memory":"16Mi"}}},"jwtPath":"/var/run/secrets/spiffe/jwt/token","trustDomain":""}` | SPIFFE authentication configuration When enabled, adds spiffe-helper sidecar to customAlloy for JWT token refresh. For destinations using SPIFFE, set auth.type: bearerToken with bearerTokenFile. |
| spiffe.collectors | list | `[]` | Upstream collectors that should receive the spiffe-helper sidecar so they can authenticate to SPIFFE (bearerToken) destinations. Valid values: alloy-logs, alloy-receiver, alloy-metrics. Replaces the manual collectorCommon sidecar injection. |
| telemetryServices | object | `{"kube-state-metrics":{"deploy":false},"node-exporter":{"deploy":false}}` | Telemetry services deployment flags |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
