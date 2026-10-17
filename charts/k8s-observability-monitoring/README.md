# k8s-observability-monitoring

![Version: 1.10.1](https://img.shields.io/badge/Version-1.10.1-informational?style=flat-square) ![AppVersion: 4.5.3](https://img.shields.io/badge/AppVersion-4.5.3-informational?style=flat-square)

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
- with upstream 4.5.x: `kyverno/vpa-webhook`, `cnpg-system/kyverno-cleanup-controller`, ... (changing per scrape)

**Root cause** (reproduced 2026-10-17 by running live kube-state-metrics output through
the pipeline upstream `k8s-monitoring` 4.5.3 renders): kube-state-metrics'
`kube_{mutating,validating}webhookconfiguration_webhook_clientconfig_service` series carry
the webhook's backing service as `service_name` / `service_namespace` labels (e.g.
`service_namespace="cert-manager"`). Upstream's OTLP destination promotes those datapoint
attributes to the `service.name` / `service.namespace` resource attributes, and all series of
one scrape share a single resource, so one webhook series rewrites the identity of *every*
kube-state-metrics series in that scrape. The OTLP endpoint then builds
`job = service.namespace/service.name`. 4.5.x made it worse: the new
`<destination>_scrape_normalize` transform overwrites `service.name` unconditionally.

Upstream's *own* kube-state-metrics scrape (`clusterMetrics`) is clean by default, because
its default allow list drops the webhook series. It breaks when the full metric set reaches
the OTLP destination: KPS's kube-state-metrics ServiceMonitor picked up by
`prometheusOperatorObjects` (hence "only with KPS"), or `useDefaultAllowList: false`.

> **Note:** earlier revisions of this chart blamed Alloy *clustering*, and later the
> promotion of kube-state-metrics' `namespace` label. Neither is the trigger: it is the
> webhook series' own `service_*` labels.

### The Solution

The chart handles it whichever collector scrapes kube-state-metrics:

1. When kube-state-metrics is scraped directly (`customAlloy.enabled`, or `clusterMetrics.enabled`
   with its kube-state-metrics scrape on), its ServiceMonitor is excluded from
   `prometheusOperatorObjects`, so it is never scraped twice.
2. `clusterMetrics`: the chart prepends two relabel rules to the kube-state-metrics scrape that
   rename `service_name` / `service_namespace` to `webhook_service_name` /
   `webhook_service_namespace` before the OTLP conversion. The webhook data is kept, the job label stays clean.
3. `customAlloy`: its pipeline never promotes those labels (keep `attributePromotion.enabled: false`).

### Retiring customAlloy

customAlloy is no longer required for the job-label bug: the upstream collectors do the same
job with `clusterMetrics` (verified end-to-end with live kube-state-metrics data: full metric
set, clean `integrations/kubernetes/kube-state-metrics` job on every scrape). To move a cluster
over:

```yaml
customAlloy:
  enabled: false
clusterMetrics:
  enabled: true
  kube-state-metrics:
    namespace: prometheus             # reuse the existing (KPS) kube-state-metrics...
    labelMatchers:
      app.kubernetes.io/name: kube-state-metrics
    metricsTuning:
      useDefaultAllowList: false      # ...with the full metric set customAlloy shipped
  kubelet:
    nodeAddressFormat: proxy          # customAlloy scraped kubelet/cadvisor via the API server
  cadvisor:
    nodeAddressFormat: proxy
```

| customAlloy | Upstream equivalent |
|---|---|
| kube-state-metrics scrape, `kubeStateMetrics.namespace` | `clusterMetrics.kube-state-metrics` (`namespace`, `labelMatchers`) |
| `kubeStateMetrics.extraMetricProcessingRules` | `clusterMetrics.kube-state-metrics.extraMetricProcessingRules` |
| `kubelet.enabled` (kubelet + cadvisor) | `clusterMetrics.kubelet` / `cadvisor`, `nodeAddressFormat: proxy` |
| node-exporter scrape, `nodeExporter.extraMetricProcessingRules` | an existing node-exporter ServiceMonitor (e.g. KPS) via `prometheusOperatorObjects`. Upstream v4 moved node-exporter to the `hostMetrics` feature, which this chart does not expose yet |
| `replaceUpstreamCollector` (ServiceMonitors, PodMonitors, Probes) | `prometheusOperatorObjects` (see the blocker below) |
| `extraConfig` | `collectors.alloy-metrics.extraConfig`, forwarding to `otelcol.receiver.prometheus.<destination>.receiver` |
| `clustering`, `replicas` | `alloy-metrics` presets `[clustered, statefulset]` (already set) |
| `sendingQueue`, `memoryLimiter` | `destinations.<name>.sendingQueue`, `destinations.<name>.processors.memoryLimiter` |
| `attributeCleanup` | upstream default (same `delete_key` list) |
| `resources`, `vpa`, `priorityClassName`, `livenessProbe` | `collectors.alloy-metrics.alloy.resources`, `.controller.autoscaling.vertical`, `.controller.priorityClassName`, `.alloy.livenessProbe` |
| `spiffe` sidecar | `spiffe.collectors: [alloy-metrics]` |
| `customAlloyOnly` destinations | drop the flag: `tenantId`, `insecure`, `insecureSkipVerify` are passed to upstream |

Expect these differences in the data after the switch:
- kube-state-metrics series get `instance` = the endpoint `ip:port` instead of the node name (one-off series churn).
- the webhook clientconfig series carry `webhook_service_name` / `webhook_service_namespace` instead of `service_name` / `service_namespace`.
- kubelet/cadvisor follow upstream's allow lists instead of customAlloy's drop rules.

**Blocker: KPS system ServiceMonitors.** With `replaceUpstreamCollector`, customAlloy scrapes
KPS's kube-apiserver, kubelet, coredns, kube-controller-manager, kube-scheduler, kube-etcd and
kube-proxy ServiceMonitors by setting `allow_arbitrary_file_access` (they use
`bearerTokenFile`). Upstream's `prometheusOperatorObjects` (4.5.3) has no such option, so
alloy-metrics drops them with only an error log. Keep customAlloy on clusters that depend on those
metrics, or switch to upstream's `clusterMetrics.apiServer` / `kubeDNS` / ... scrapes (job labels
become `integrations/kubernetes/*`, so dashboards need updating), until upstream supports it.

Once no cluster runs customAlloy, it can be deleted from the chart (a breaking, major version change).

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

## Memory limiter

An `otelcol.processor.memory_limiter` makes a collector refuse data (and force GCs)
once it nears its memory budget, instead of being OOMKilled. All three are off by
default and can be set independently:

| Where | Value | Placement | Notes |
|---|---|---|---|
| customAlloy pipeline | `customAlloy.memoryLimiter` | right after `otelcol.receiver.prometheus`, so it also covers `extraConfig` pipelines | Percentage of the container memory limit by default, or a fixed `limit` |
| alloy-receiver (application OTLP) | `applicationObservability.processors.memoryLimiter` | right after the OTLP/Jaeger/Zipkin receivers | Passed through to upstream; fixed `limit` only. Senders get a retryable error and back off |
| per destination, upstream collectors | `destinations.<name>.processors.memoryLimiter` | upstream puts it after the destination's batch processor | Passed through to upstream; fixed `limit` only. Ignored by customAlloy |

```yaml
customAlloy:
  memoryLimiter:
    enabled: true
    limitPercentage: 80        # hard limit: 80% of customAlloy.resources.limits.memory
    spikeLimitPercentage: 20   # soft limit: 80 - 20 = 60% (refuses data from here on)
    # limit: 1600MiB           # or a fixed limit instead of the percentages

applicationObservability:
  processors:
    memoryLimiter:
      enabled: true
      checkInterval: 1s
      limit: 400MiB            # below the alloy-receiver container memory limit
```

customAlloy scrapes are pull-based, so data refused there is dropped, not retried:
expect gaps rather than a restart. The percentage is resolved when the component starts,
so when VPA changes the memory limit in place the limiter picks it up at the next
pod restart. The chart rejects a percentage-mode config without
`customAlloy.resources.limits.memory`, because the percentage would then be taken of
node memory.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| applicationObservability | object | `{"destinations":[],"enabled":false,"processors":{},"receivers":{"otlp":{"grpc":{"enabled":true,"port":4317},"http":{"enabled":true,"port":4318}}}}` | Application observability (OTLP receiver for traces, metrics, logs from apps) |
| applicationObservability.processors | object | `{}` | Processor settings passed through verbatim to the upstream applicationObservability feature (see its values for the full list). E.g. a memory limiter right after the OTLP receiver of alloy-receiver, which pushes back on senders with a retryable error instead of letting the collector OOM:   processors:     memoryLimiter:       enabled: true       checkInterval: 1s       limit: 400MiB   # upstream only supports an absolute limit; keep it below                       # the alloy-receiver container memory limit |
| autoInstrumentation | object | `{"destinations":[],"enabled":false}` | Auto-instrumentation for applications |
| chart | object | `{"version":""}` | Override the upstream chart version (defaults to appVersion in Chart.yaml) |
| clusterMetrics | object | `{"destinations":[],"enabled":false,"kube-state-metrics":{},"kubelet":{"enabled":true,"metricsTuning":{"useDefaultAllowList":true},"nodeAddressFormat":"direct"},"kubeletResource":{"enabled":true,"nodeAddressFormat":"direct"}}` | Cluster metrics (kubelet, cadvisor, kube-state-metrics, control plane, ...) scraped by the upstream alloy-metrics collector -- the replacement for customAlloy (see "Retiring customAlloy" in the README). Keys other than the ones below (cadvisor, apiServer, kubeDNS, ...) are passed through to upstream clusterMetrics verbatim when enabled. |
| clusterMetrics.kube-state-metrics | object | `{}` | Upstream kube-state-metrics scrape settings, passed through (namespace, labelMatchers, metricsTuning, extraMetricProcessingRules, ...). The chart always prepends two relabel rules that rename KSM's webhook `service_name`/`service_namespace` labels to `webhook_service_*`: left alone, upstream's OTLP destination copies them onto the scrape's resource and every KSM series gets a garbage job label (e.g. `kyverno/vpa-webhook`). The upstream default allow list drops those series anyway; the rules matter once useDefaultAllowList is false. Requires telemetryServices.kube-state-metrics.deploy, or pointing at an existing instance:   kube-state-metrics:     namespace: prometheus          # e.g. kube-prometheus-stack's kube-state-metrics     labelMatchers:       app.kubernetes.io/name: kube-state-metrics     metricsTuning:       useDefaultAllowList: false   # full metric set, like customAlloy |
| clusterName | string | `""` | Cluster name for telemetry labeling. Must be set to a non-empty value at install time. |
| collectorCommon | object | `{"alloy":{"alloy":{"resources":{"limits":{"memory":"1Gi"},"requests":{"cpu":"100m","memory":"512Mi"}}},"controller":{"affinity":{"nodeAffinity":{"requiredDuringSchedulingIgnoredDuringExecution":{"nodeSelectorTerms":[{"matchExpressions":[{"key":"eks.amazonaws.com/compute-type","operator":"NotIn","values":["fargate"]}]}]}}},"autoscaling":{"vertical":{"enabled":false,"resourcePolicy":{"containerPolicies":[{"containerName":"alloy","controlledResources":["memory"],"maxAllowed":{"memory":"4Gi"},"minAllowed":{"memory":"256Mi"}}]},"updatePolicy":{"updateMode":"Auto"}}}}}}` | Common collector settings (applies to all Alloy instances managed by operator). NOTE: collectorCommon.alloy is merged at the *top level* of each Alloy custom resource's spec (siblings: alloy, controller, ...) -- see grafana/k8s-monitoring-helm collector.alloy.values. That means resources must be nested under an inner `alloy:` key (collectorCommon.alloy.alloy.resources), not collectorCommon.alloy.resources directly, or they silently land on an unknown top-level field and are dropped -- each managed collector then falls back to its preset's resources instead. |
| collectorCommon.alloy.controller | object | `{"affinity":{"nodeAffinity":{"requiredDuringSchedulingIgnoredDuringExecution":{"nodeSelectorTerms":[{"matchExpressions":[{"key":"eks.amazonaws.com/compute-type","operator":"NotIn","values":["fargate"]}]}]}}},"autoscaling":{"vertical":{"enabled":false,"resourcePolicy":{"containerPolicies":[{"containerName":"alloy","controlledResources":["memory"],"maxAllowed":{"memory":"4Gi"},"minAllowed":{"memory":"256Mi"}}]},"updatePolicy":{"updateMode":"Auto"}}}}` | Controller settings for pod scheduling and autoscaling |
| collectorCommon.alloy.controller.affinity | object | `{"nodeAffinity":{"requiredDuringSchedulingIgnoredDuringExecution":{"nodeSelectorTerms":[{"matchExpressions":[{"key":"eks.amazonaws.com/compute-type","operator":"NotIn","values":["fargate"]}]}]}}}` | Node affinity to prevent DaemonSets from scheduling on Fargate nodes. Fargate doesn't support DaemonSets, so we exclude nodes with eks.amazonaws.com/compute-type=fargate. |
| collectorCommon.alloy.controller.autoscaling | object | `{"vertical":{"enabled":false,"resourcePolicy":{"containerPolicies":[{"containerName":"alloy","controlledResources":["memory"],"maxAllowed":{"memory":"4Gi"},"minAllowed":{"memory":"256Mi"}}]},"updatePolicy":{"updateMode":"Auto"}}}` | VerticalPodAutoscaler for upstream-managed collectors (alloy-metrics, alloy-logs, alloy-receiver), using the Alloy Operator's native VPA support -- no custom template needed. Disabled by default: unlike customAlloy (opt-in feature, so its VPA default-on only affects clusters that already enabled it), alloy-metrics/alloy-logs are core collectors enabled on every install, and this requires the VPA CRD to be present in the cluster. Enable per-cluster once the VPA CRD is confirmed installed. |
| collectors | object | `{"alloy-logs":{"alloy":{"resources":{"limits":{"memory":"512Mi"},"requests":{"cpu":"100m","memory":"256Mi"}}}}}` | Per-collector settings (overrides collectorCommon for specific collectors) Available collectors: alloy-logs, alloy-metrics, alloy-receiver |
| customAlloy | object | `{"attributeCleanup":{"enabled":true},"attributePromotion":{"enabled":false},"clustering":{"enabled":false},"enabled":false,"extraConfig":"","kubeStateMetrics":{"extraMetricProcessingRules":"","namespace":""},"kubelet":{"enabled":false},"liveDebugging":{"enabled":true},"livenessProbe":{"failureThreshold":3,"initialDelaySeconds":30,"periodSeconds":10,"timeoutSeconds":5},"memoryLimiter":{"checkInterval":"1s","enabled":false,"limit":"","limitPercentage":80,"spikeLimit":"","spikeLimitPercentage":20},"nodeExporter":{"extraMetricProcessingRules":""},"priorityClassName":"","readinessProbe":{"failureThreshold":3,"initialDelaySeconds":10,"periodSeconds":5,"timeoutSeconds":5},"replaceUpstreamCollector":false,"replicas":1,"resources":{"limits":{"memory":"2Gi"},"requests":{"cpu":"100m","memory":"1Gi"}},"sendingQueue":{"enabled":true,"numConsumers":10,"queueSize":500},"vpa":{"enabled":true,"maxAllowed":{"memory":"2Gi"},"minAllowed":{"memory":"512Mi"},"updateMode":"InPlaceOrRecreate"}}` | Custom Alloy deployment for kube-state-metrics scraping Deploys separate Alloy instance with OTEL pipeline for metrics. This is preserved from v3.x to maintain the workaround for duplicate job labels. |
| customAlloy.extraConfig | string | `""` | Raw Alloy configuration appended verbatim to the custom Alloy config.alloy. Use it to add pipelines the chart does not model, e.g. a prometheus.scrape of targets outside the cluster. Forward metrics to otelcol.receiver.prometheus.default.receiver to reuse the chart's OTLP pipeline (batching, auth, destinations). Not passed through tpl. When clustering.enabled is true, add `clustering { enabled = true }` to scrape blocks so the targets are sharded across replicas instead of being scraped once per replica. |
| customAlloy.kubeStateMetrics.namespace | string | `""` | Restrict kube-state-metrics discovery to a single namespace. Empty (default) discovers any kube-state-metrics-labeled endpoint cluster-wide, which double-counts every series if more than one instance exists (e.g. this chart's own, deployed via telemetryServices.kube-state-metrics, alongside a platform-managed one). Set to the namespace of the instance you want scraped once you have exactly one you intend to use. |
| customAlloy.livenessProbe | object | `{"failureThreshold":3,"initialDelaySeconds":30,"periodSeconds":10,"timeoutSeconds":5}` | Liveness probe for the alloy container. timeoutSeconds defaults to 5 (not Kubernetes' implicit 1s) because this single binary also runs OTLP export queues/retries and (when clustering is enabled) gossip -- a busy retry loop against a slow/unhealthy destination can otherwise delay the health handler past a 1s budget and trip the probe even though alloy itself is fine. |
| customAlloy.memoryLimiter | object | `{"checkInterval":"1s","enabled":false,"limit":"","limitPercentage":80,"spikeLimit":"","spikeLimitPercentage":20}` | Optional otelcol.processor.memory_limiter at the head of the OTEL pipeline (receiver.prometheus -> memory_limiter -> transform -> batch -> exporters), so it also covers anything extraConfig forwards into the receiver. Above the soft limit (limit minus spike) it refuses incoming data; above the hard limit it forces a GC. Scrapes are pull-based, so refused samples are dropped rather than retried: it trades gaps in the data for not being OOMKilled (and losing the WAL and sending queue with it). |
| customAlloy.memoryLimiter.checkInterval | string | `"1s"` | How often memory usage is checked. |
| customAlloy.memoryLimiter.limit | string | `""` | Absolute mode: fixed hard limit (e.g. "1600MiB"). When set it replaces the percentage pair (Alloy accepts one mode or the other, not both). Keep it below the container memory limit, and remember VPA can change that limit. |
| customAlloy.memoryLimiter.limitPercentage | int | `80` | Percentage mode (used when limit is empty): hard limit as a % of the container memory limit, so it follows customAlloy.resources.limits.memory and VPA changes to it. Read once at component start: an in-place VPA resize takes effect on the next pod restart. Requires a container memory limit. |
| customAlloy.memoryLimiter.spikeLimit | string | `""` | Absolute mode: spike headroom (e.g. "320MiB"). Empty = Alloy's default, 20% of limit. |
| customAlloy.memoryLimiter.spikeLimitPercentage | int | `20` | Percentage mode: spike headroom (% of the container memory limit). The soft limit is limitPercentage - spikeLimitPercentage. Must be below limitPercentage. |
| customAlloy.priorityClassName | string | `""` | PriorityClass for the customAlloy pods. Empty (default) leaves them at the cluster default priority, like the upstream alloy-metrics/alloy-receiver collectors. |
| customAlloy.readinessProbe | object | `{"failureThreshold":3,"initialDelaySeconds":10,"periodSeconds":5,"timeoutSeconds":5}` | Readiness probe for the alloy container. Same timeoutSeconds rationale as livenessProbe above. |
| customAlloy.replaceUpstreamCollector | bool | `false` | Replace upstream alloy-metrics collector entirely. |
| customAlloy.vpa | object | `{"enabled":true,"maxAllowed":{"memory":"2Gi"},"minAllowed":{"memory":"512Mi"},"updateMode":"InPlaceOrRecreate"}` | VerticalPodAutoscaler for customAlloy. Enabled by default: clustering deployments outgrow the static requests under real metric volume and OOMKill at fixed limits. VPA (memory-only) right-sizes them within min/maxAllowed. maxAllowed is deliberately capped well below the admission controller's old 8Gi ceiling: a single stale/transient memory peak (e.g. a WAL or ingest burst) could otherwise drive the recommender target -- and thus the live request/limit -- up to that ceiling and keep it there long after the spike passed, even though steady-state usage is under 1Gi. 2Gi still leaves headroom above observed usage for genuine growth before it needs revisiting. |
| daemonSetPriorityClassName | string | `"system-node-critical"` | PriorityClass for the per-node DaemonSets this chart deploys: alloy-logs, and node-exporter when telemetryServices.node-exporter.deploy is true. Defaults to the built-in system-node-critical, matching the platform's own per-node agents (fluent-bit, kps-node-exporter, spire-agent, cilium): a DaemonSet pod with the default priority 0 can't preempt anything, so on a full node (e.g. a fresh Karpenter node packed before the DaemonSet pod lands) it stays Pending and that node's logs are silently never collected. A per-collector collectors.alloy-logs.controller.priorityClassName still takes precedence. Set to "" to leave the pods at the cluster default priority. |
| dedicatedNodeToleration | object | `{"effect":"NoSchedule","enabled":true,"key":"cilium.hsp.philips.com/dedicated","operator":"Exists","value":""}` | Toleration for the platform's "dedicated node" taint key (e.g. the kafka/tempo-kafka dedicated nodes created by mimir-bootstrap/tempo-bootstrap's kafkaNodePool), so the DaemonSets this chart deploys -- alloy-logs for node logs, and node-exporter for host metrics when enabled -- still land on those nodes. Defaults to operator: Exists (no value match) since different bootstrap charts taint their dedicated nodes with different values under the same key (mimir-bootstrap: "kafka", tempo-bootstrap: "tempo-kafka") -- matching on the key alone covers all of them, including any added in the future, without further chart changes. Set operator: Equal and value: <taint-value> to match one value only. |
| destinations | object | `{}` | OTLP destinations where telemetry data will be sent. Each destination is a map entry with the destination name as key. See: https://github.com/grafana/k8s-monitoring-helm/blob/main/charts/k8s-monitoring/docs/destinations/README.md  Set customAlloyOnly: true to exclude a destination from the upstream k8s-monitoring chart (it will only be used by customAlloy). tenantId (X-Scope-OrgID), insecure and insecureSkipVerify apply to both customAlloy and upstream, so a no-auth customAlloyOnly destination can drop the flag and be used by the upstream collectors instead.  Example:   destinations:     otlpGateway:       type: otlp       url: "https://otlp-gateway.example.com/otlp"       protocol: http       auth:         type: basic         usernameKey: "username"         passwordKey: "apiKey"       secret:         create: false         name: "otlp-gateway-creds"       metrics:         enabled: true       logs:         enabled: true       traces:         enabled: true       processors:         batch:           enabled: true           size: 2000       sendingQueue:         enabled: true         queueSize: 100 |
| hubbleFlowLogs | object | `{"batchMaxSize":512,"destinations":[],"enabled":false,"exportFilePath":"/var/run/cilium/hubble/events.log"}` | Cilium Hubble L7 flow/access logs collection. Tails Cilium's flow export file on each node (via the alloy-logs DaemonSet) and ships it to a destination as OTLP logs. The chart does NOT configure Cilium: the operator must enable hubble.export on the Cilium side (file path below + allowlist event_type 129). Requires alloy-logs to have SPIFFE auth if a target destination uses bearerToken auth: add "alloy-logs" to spiffe.collectors. |
| hubbleFlowLogs.batchMaxSize | int | `512` | Max OTLP batch size for flows. Hubble flow JSON is large (~4.5 KB/flow); keep batches under the gateway's gRPC receive limit (commonly 4 MB). 512 ~= 2.3 MB. |
| hubbleFlowLogs.destinations | list | `[]` | Destinations to ship flows to. Empty = reuse the destinations resolved for podLogsViaLoki. |
| hubbleFlowLogs.exportFilePath | string | `"/var/run/cilium/hubble/events.log"` | Cilium hubble-export-file-path. The chart mounts this file's parent dir read-only. |
| kyverno | object | `{"policyException":{"enabled":false,"policyName":"enforce-baseline-pod-security-profile","ruleNames":["enforce-baseline-profile"]}}` | Kyverno PolicyException configuration |
| podLogsViaLoki | object | `{"destinations":[],"dropKubeProbe":false,"enabled":true,"excludeNamespaces":[]}` | Pod logs collection via Loki format |
| podLogsViaLoki.dropKubeProbe | bool | `false` | Drop kube-probe logs (liveness/readiness probe requests). |
| podLogsViaLoki.excludeNamespaces | list | `[]` | Namespaces to exclude from log collection. |
| project | object | `{"name":"default"}` | ArgoCD project name for the k8s-monitoring Application |
| prometheusOperatorObjects | object | `{"allowArbitraryFileAccess":true,"destinations":[],"enabled":true,"serviceMonitors":{"extraDiscoveryRules":"","extraMetricProcessingRules":"","labelExpressions":[],"metricsTuning":{"excludeMetrics":[]}}}` | Prometheus Operator Objects (ServiceMonitors, PodMonitors, Probes) |
| prometheusOperatorObjects.destinations | list | `[]` | Destinations to send metrics. Empty = all metrics-capable destinations. |
| prometheusOperatorObjects.serviceMonitors.extraDiscoveryRules | string | `""` | Extra discovery rules for ServiceMonitors (Alloy relabel config syntax). |
| prometheusOperatorObjects.serviceMonitors.extraMetricProcessingRules | string | `""` | Extra metric processing rules (Alloy relabel config syntax). |
| prometheusOperatorObjects.serviceMonitors.labelExpressions | list | `[]` | Label expressions to filter which ServiceMonitors to scrape. |
| prometheusOperatorObjects.serviceMonitors.metricsTuning | object | `{"excludeMetrics":[]}` | Metrics tuning to filter metrics. |
| prometheusOperatorObjects.serviceMonitors.metricsTuning.excludeMetrics | list | `[]` | Metrics to exclude. Can use regular expressions. Example: ["apiserver_request_duration_seconds_bucket"] |
| spiffe | object | `{"audience":"","collectors":[],"enabled":false,"helper":{"image":"ghcr.io/spiffe/spiffe-helper:0.12.2","resources":{"limits":{"memory":"32Mi"},"requests":{"cpu":"1m","memory":"16Mi"}}},"jwtPath":"/var/run/secrets/spiffe/jwt/token","trustDomain":""}` | SPIFFE authentication configuration When enabled, adds spiffe-helper sidecar to customAlloy for JWT token refresh. For destinations using SPIFFE, set auth.type: bearerToken with bearerTokenFile. |
| spiffe.collectors | list | `[]` | Upstream collectors that should receive the spiffe-helper sidecar so they can authenticate to SPIFFE (bearerToken) destinations. Valid values: alloy-logs, alloy-receiver, alloy-metrics. Replaces the manual collectorCommon sidecar injection. |
| telemetryServices | object | `{"kube-state-metrics":{"deploy":false},"node-exporter":{"deploy":false}}` | Telemetry services deployment flags |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
