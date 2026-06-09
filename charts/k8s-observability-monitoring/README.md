# k8s-observability-monitoring

![Version: 1.1.0](https://img.shields.io/badge/Version-1.1.0-informational?style=flat-square) ![AppVersion: 4.1.3](https://img.shields.io/badge/AppVersion-4.1.3-informational?style=flat-square)

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

This is caused by a combination of:
1. Alloy's clustering feature prefixing job labels with namespace information
2. OTEL attribute promotion interfering with job label derivation

See: https://github.com/grafana/k8s-monitoring-helm/issues/2383

### The Solution

Enable `customAlloy` which deploys a dedicated Alloy instance for kube-state-metrics scraping without the problematic features:

```yaml
# values.yaml for clusters with KPS
customAlloy:
  enabled: true
  clustering:
    enabled: false  # Avoid job label prefix bug
  attributePromotion:
    enabled: false  # Avoid service.namespace promotion bug

# kube-state-metrics exclusion is automatically added when customAlloy.enabled: true
```

This configuration:
1. Deploys a dedicated Alloy instance that scrapes kube-state-metrics directly with correct job labels
2. Automatically excludes the kube-state-metrics ServiceMonitor from `prometheusOperatorObjects` to avoid duplicates

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
| customAlloy | object | `{"attributeCleanup":{"enabled":true},"attributePromotion":{"enabled":false},"clustering":{"enabled":false},"enabled":false,"kubeStateMetrics":{"extraMetricProcessingRules":""},"kubelet":{"enabled":false},"liveDebugging":{"enabled":true},"replaceUpstreamCollector":false,"replicas":1,"resources":{"limits":{"memory":"1Gi"},"requests":{"cpu":"100m","memory":"512Mi"}},"sendingQueue":{"enabled":true,"numConsumers":10,"queueSize":500},"vpa":{"enabled":false,"maxAllowed":{"memory":"8Gi"},"minAllowed":{"memory":"512Mi"},"updateMode":"InPlaceOrRecreate"}}` | Custom Alloy deployment for kube-state-metrics scraping Deploys separate Alloy instance with OTEL pipeline for metrics. This is preserved from v3.x to maintain the workaround for duplicate job labels. |
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
