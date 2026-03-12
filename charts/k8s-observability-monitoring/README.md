# k8s-observability-monitoring

![Version: 0.21.0](https://img.shields.io/badge/Version-0.21.0-informational?style=flat-square) ![AppVersion: 3.8.0](https://img.shields.io/badge/AppVersion-3.8.0-informational?style=flat-square)

Helm chart for k8s-observability-monitoring

## Installing on clusters with kube-prometheus-stack (KPS)

If your cluster already has [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) installed, you need additional configuration to avoid duplicate metrics.

### The Problem

Alloy's `prometheus.operator.servicemonitors` component has a [known bug](https://github.com/grafana/k8s-monitoring-helm/issues/1799) that creates duplicate scrape jobs from a single ServiceMonitor. For kube-state-metrics, this results in two jobs (e.g., `cert-manager/kube-state-metrics` and `prometheus/kube-state-metrics`) scraping the same data, causing double counts in dashboards.

### The Solution

Use `labelExpressions` to exclude kube-state-metrics from ServiceMonitor scraping, and enable `clusterMetrics` to scrape it directly instead:

```yaml
# values.yaml for clusters with KPS
features:
  clusterMetrics: true  # Enable direct kube-state-metrics scraping

prometheusOperatorObjects:
  serviceMonitors:
    labelExpressions:
      - key: "app.kubernetes.io/name"
        operator: "NotIn"
        values:
          - "kube-state-metrics"

clusterMetrics:
  kubeStateMetrics:
    enabled: true
    deploy: false  # Use existing KPS deployment
    labelMatchers:
      app.kubernetes.io/name: kube-state-metrics
  nodeExporter:
    enabled: true
    deploy: false  # Use existing KPS deployment
```

This configuration:
1. Excludes the kube-state-metrics ServiceMonitor from being scraped by `prometheusOperatorObjects` (avoiding the duplicate bug)
2. Uses the built-in `clusterMetrics` feature to scrape kube-state-metrics directly via `integrations/kubernetes/kube-state-metrics`
3. Does not deploy new kube-state-metrics or node-exporter instances (uses existing KPS deployments)

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

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| chart | object | `{"version":""}` | Override the upstream chart version (defaults to appVersion in Chart.yaml) |
| clusterMetrics | object | `{"kubeStateMetrics":{"deploy":false,"enabled":true,"labelMatchers":{"app.kubernetes.io/name":"kube-state-metrics"},"namespace":""},"nodeExporter":{"deploy":false,"enabled":true}}` | Cluster metrics configuration (kube-state-metrics, node-exporter, kubelet, etc.) Only used when features.clusterMetrics is true. |
| clusterMetrics.kubeStateMetrics.deploy | bool | `false` | Deploy kube-state-metrics (set to false if using existing deployment) |
| clusterMetrics.kubeStateMetrics.enabled | bool | `true` | Enable scraping kube-state-metrics |
| clusterMetrics.kubeStateMetrics.labelMatchers | object | `{"app.kubernetes.io/name":"kube-state-metrics"}` | Label matchers to find kube-state-metrics service |
| clusterMetrics.kubeStateMetrics.namespace | string | `""` | Namespace where kube-state-metrics is deployed (auto-detected if empty) |
| clusterMetrics.nodeExporter.deploy | bool | `false` | Deploy node-exporter (set to false if using existing deployment) |
| clusterMetrics.nodeExporter.enabled | bool | `true` | Enable scraping node-exporter |
| clusterName | string | `"changeme"` |  |
| features | object | `{"autoInstrumentation":false,"clusterMetrics":false,"prometheusOperatorObjects":true}` | Feature toggles |
| features.autoInstrumentation | bool | `false` | Enable auto-instrumentation for application telemetry |
| features.clusterMetrics | bool | `false` | Enable cluster metrics collection (kube-state-metrics, node-exporter, kubelet, etc.) Set to false if using kube-prometheus-stack which provides these via ServiceMonitors. |
| features.prometheusOperatorObjects | bool | `true` | Enable scraping Prometheus Operator objects (ServiceMonitors, PodMonitors, Probes). |
| otlp | object | `{"destinations":[]}` | OTLP destination configuration for sending telemetry data (metrics, logs, traces) |
| otlp.destinations | list | `[]` | List of OTLP destinations to send telemetry data to. Each destination requires a pre-created Kubernetes Secret with basic auth credentials.  Secret format:   The secret must contain the following keys:   - username: The username for basic authentication   - apiKey: The API key or password for basic authentication  Example secret creation:   kubectl create secret generic otlp-gateway-creds \     --from-literal=username=myuser \     --from-literal=apiKey=myapikey  Or via YAML:   apiVersion: v1   kind: Secret   metadata:     name: otlp-gateway-creds   type: Opaque   stringData:     username: "myuser"     apiKey: "myapikey"  |
| project | object | `{"name":"default"}` | ArgoCD project name for the k8s-monitoring Application |
| prometheusOperatorObjects | object | `{"serviceMonitors":{"extraDiscoveryRules":"","extraMetricProcessingRules":"","labelExpressions":[]}}` | Prometheus Operator Objects configuration |
| prometheusOperatorObjects.serviceMonitors.extraDiscoveryRules | string | `""` | Extra discovery rules for ServiceMonitors (Alloy relabel config syntax). Applied before scraping to filter/transform targets. |
| prometheusOperatorObjects.serviceMonitors.extraMetricProcessingRules | string | `""` | Extra metric processing rules for ServiceMonitors (Alloy relabel config syntax). Use this to filter/transform metrics after scraping. |
| prometheusOperatorObjects.serviceMonitors.labelExpressions | list | `[]` | Label expressions to filter which ServiceMonitors to scrape. Empty by default (scrape all). Example to exclude kube-state-metrics:   - key: "app.kubernetes.io/name"     operator: "NotIn"     values:       - "kube-state-metrics" |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
