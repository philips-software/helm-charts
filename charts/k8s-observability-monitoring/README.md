# k8s-observability-monitoring

![Version: 0.36.0](https://img.shields.io/badge/Version-0.36.0-informational?style=flat-square) ![AppVersion: 3.8.3](https://img.shields.io/badge/AppVersion-3.8.3-informational?style=flat-square)

Helm chart for k8s-observability-monitoring

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

# Exclude kube-state-metrics from ServiceMonitor scraping (handled by customAlloy)
prometheusOperatorObjects:
  serviceMonitors:
    labelExpressions:
      - key: "app.kubernetes.io/name"
        operator: "NotIn"
        values:
          - "kube-state-metrics"
```

This configuration:
1. Deploys a dedicated Alloy instance that scrapes kube-state-metrics directly with correct job labels
2. Excludes the kube-state-metrics ServiceMonitor from `prometheusOperatorObjects` to avoid duplicates
3. The customAlloy exclusion is automatically added when `customAlloy.enabled: true`

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
| alloyLogs | object | `{"resources":{"limits":{"memory":"200Mi"},"requests":{"cpu":"50m","memory":"100Mi"}}}` | Alloy Logs resource configuration |
| alloyMetrics | object | `{"resources":{"limits":{"memory":"3Gi"},"requests":{"cpu":"300m","memory":"1536Mi"}}}` | Alloy Metrics resource configuration |
| chart | object | `{"version":""}` | Override the upstream chart version (defaults to appVersion in Chart.yaml) |
| clusterMetrics | object | `{"kubeStateMetrics":{"deploy":false,"enabled":true,"extraMetricProcessingRules":"","labelMatchers":{"app.kubernetes.io/name":"kube-state-metrics"},"namespace":"","useDefaultAllowList":false},"kubelet":{"enabled":true,"nodeAddressFormat":"direct","useDefaultAllowList":true},"kubeletResource":{"enabled":true,"nodeAddressFormat":"direct"},"nodeExporter":{"deploy":false,"enabled":true}}` | Cluster metrics configuration (kube-state-metrics, node-exporter, kubelet, etc.) Only used when features.clusterMetrics is true. |
| clusterMetrics.kubeStateMetrics.deploy | bool | `false` | Deploy kube-state-metrics (set to false if using existing deployment) |
| clusterMetrics.kubeStateMetrics.enabled | bool | `true` | Enable scraping kube-state-metrics |
| clusterMetrics.kubeStateMetrics.extraMetricProcessingRules | string | `""` | Extra metric processing rules for kube-state-metrics (Alloy relabel config syntax). Use this to filter/transform metrics after scraping. Example to drop duplicate scrape jobs caused by Alloy clustering bug:   rule {     source_labels = ["job"]     regex = "crossplane-system/integrations/kubernetes/kube-state-metrics"     action = "drop"   } |
| clusterMetrics.kubeStateMetrics.labelMatchers | object | `{"app.kubernetes.io/name":"kube-state-metrics"}` | Label matchers to find kube-state-metrics service |
| clusterMetrics.kubeStateMetrics.namespace | string | `""` | Namespace where kube-state-metrics is deployed (auto-detected if empty) |
| clusterMetrics.kubeStateMetrics.useDefaultAllowList | bool | `false` | Use the default allowlist of metrics (true) or scrape all metrics (false). Set to false to get all kube-state-metrics including kube_service_info, kube_endpoint_info, etc. |
| clusterMetrics.kubelet.enabled | bool | `true` | Enable scraping kubelet metrics (includes volume stats for PVC monitoring) |
| clusterMetrics.kubelet.nodeAddressFormat | string | `"direct"` | How to access the Kubelet: "direct" (use node IP) or "proxy" (use API Server) |
| clusterMetrics.kubelet.useDefaultAllowList | bool | `true` | Use the default allowlist of metrics (true) or scrape all metrics (false) |
| clusterMetrics.kubeletResource.enabled | bool | `true` | Enable scraping kubelet resource metrics (CPU, memory per pod/container) |
| clusterMetrics.kubeletResource.nodeAddressFormat | string | `"direct"` | How to access the Kubelet: "direct" (use node IP) or "proxy" (use API Server) |
| clusterMetrics.nodeExporter.deploy | bool | `false` | Deploy node-exporter (set to false if using existing deployment) |
| clusterMetrics.nodeExporter.enabled | bool | `true` | Enable scraping node-exporter |
| clusterName | string | `""` | Cluster name for telemetry labeling. Must be set to a non-empty value at install time. |
| customAlloy | object | `{"attributeCleanup":{"enabled":true},"attributePromotion":{"enabled":false},"clustering":{"enabled":false},"enabled":false,"kubeStateMetrics":{"extraMetricProcessingRules":""},"kubelet":{"enabled":false},"liveDebugging":{"enabled":true},"replaceUpstreamCollector":false,"replicas":1,"resources":{"limits":{"memory":"1Gi"},"requests":{"cpu":"100m","memory":"512Mi"}},"sendingQueue":{"enabled":true}}` | Custom Alloy deployment for metrics scraping This deploys a separate Alloy instance that can scrape kube-state-metrics and optionally replace the upstream alloy-metrics collector entirely. |
| customAlloy.attributeCleanup | object | `{"enabled":true}` | Remove high-cardinality attributes to reduce storage costs Matches k8s-monitoring attribute cleanup |
| customAlloy.attributeCleanup.enabled | bool | `true` | Enable attribute cleanup |
| customAlloy.attributePromotion | object | `{"enabled":false}` | Promote useful attributes from datapoint to resource level |
| customAlloy.attributePromotion.enabled | bool | `false` | Enable attribute promotion (service.name, deployment.environment, etc.) NOTE: service.namespace promotion is disabled as it causes duplicate job labels with kube-state-metrics. See: https://github.com/grafana/k8s-monitoring-helm/issues/2383 |
| customAlloy.clustering | object | `{"enabled":false}` | Clustering configuration (for HA with multiple replicas) |
| customAlloy.clustering.enabled | bool | `false` | Enable clustering for multi-replica deployments. When enabled, uses StatefulSet instead of Deployment for stable pod identities. This provides better hash ring stability and ordered rolling updates. |
| customAlloy.enabled | bool | `false` | Enable custom Alloy deployment |
| customAlloy.kubeStateMetrics | object | `{"extraMetricProcessingRules":""}` | kube-state-metrics scraping configuration |
| customAlloy.kubeStateMetrics.extraMetricProcessingRules | string | `""` | Extra metric processing rules (Alloy relabel config syntax) |
| customAlloy.kubelet | object | `{"enabled":false}` | Kubelet metrics scraping configuration (includes PVC volume stats) |
| customAlloy.kubelet.enabled | bool | `false` | Enable kubelet and cAdvisor metrics scraping. Provides kubelet_volume_stats_* metrics for PVC capacity monitoring. |
| customAlloy.liveDebugging | object | `{"enabled":true}` | Live debugging via Alloy UI (port 12345) |
| customAlloy.liveDebugging.enabled | bool | `true` | Enable live debugging |
| customAlloy.replaceUpstreamCollector | bool | `false` | Replace upstream alloy-metrics collector entirely. When true, disables alloy-metrics and customAlloy handles all metrics collection including ServiceMonitors, PodMonitors, and Probes (if prometheusOperatorObjects is enabled). |
| customAlloy.replicas | int | `1` | Number of replicas |
| customAlloy.resources | object | `{"limits":{"memory":"1Gi"},"requests":{"cpu":"100m","memory":"512Mi"}}` | Resource requests and limits |
| customAlloy.sendingQueue | object | `{"enabled":true}` | Sending queue configuration for resilience during destination outages |
| customAlloy.sendingQueue.enabled | bool | `true` | Enable sending queue |
| features | object | `{"applicationObservability":false,"autoInstrumentation":false,"clusterMetrics":false,"prometheusOperatorObjects":true}` | Feature toggles |
| features.applicationObservability | bool | `false` | Enable the OTLP receiver for application telemetry (traces, metrics, logs from apps). Set to false if you don't need to receive OTLP data from applications. |
| features.autoInstrumentation | bool | `false` | Enable auto-instrumentation for application telemetry |
| features.clusterMetrics | bool | `false` | Enable cluster metrics collection (kube-state-metrics, node-exporter, kubelet, etc.) Set to false if using kube-prometheus-stack which provides these via ServiceMonitors. |
| features.prometheusOperatorObjects | bool | `true` | Enable scraping Prometheus Operator objects (ServiceMonitors, PodMonitors, Probes). |
| kyverno | object | `{"policyException":{"enabled":false,"policyName":"enforce-baseline-pod-security-profile","ruleNames":["enforce-baseline-profile"]}}` | Kyverno PolicyException configuration Creates a PolicyException to allow Alloy pods to run with required capabilities (NET_RAW) and hostPath volumes (for log collection). |
| kyverno.policyException | object | `{"enabled":false,"policyName":"enforce-baseline-pod-security-profile","ruleNames":["enforce-baseline-profile"]}` | Create a Kyverno PolicyException for Alloy pods |
| kyverno.policyException.policyName | string | `"enforce-baseline-pod-security-profile"` | Name of the Kyverno ClusterPolicy to exempt |
| kyverno.policyException.ruleNames | list | `["enforce-baseline-profile"]` | Rule names within the policy to exempt |
| otlp | object | `{"destinations":[]}` | OTLP destination configuration for sending telemetry data (metrics, logs, traces) |
| otlp.destinations | list | `[]` | List of OTLP destinations to send telemetry data to. Each destination requires a pre-created Kubernetes Secret with basic auth credentials.  Secret format:   The secret must contain the following keys:   - username: The username for basic authentication   - apiKey: The API key or password for basic authentication  Example secret creation:   kubectl create secret generic otlp-gateway-creds \     --from-literal=username=myuser \     --from-literal=apiKey=myapikey  Or via YAML:   apiVersion: v1   kind: Secret   metadata:     name: otlp-gateway-creds   type: Opaque   stringData:     username: "myuser"     apiKey: "myapikey"  |
| podLogs | object | `{"dropKubeProbe":false}` | Pod logs configuration |
| podLogs.dropKubeProbe | bool | `false` | Drop kube-probe logs (liveness/readiness probe requests). These are typically noisy and not useful for debugging. |
| project | object | `{"name":"default"}` | ArgoCD project name for the k8s-monitoring Application |
| prometheusOperatorObjects | object | `{"serviceMonitors":{"extraDiscoveryRules":"","extraMetricProcessingRules":"","labelExpressions":[]}}` | Prometheus Operator Objects configuration |
| prometheusOperatorObjects.serviceMonitors.extraDiscoveryRules | string | `""` | Extra discovery rules for ServiceMonitors (Alloy relabel config syntax). Applied before scraping to filter/transform targets. |
| prometheusOperatorObjects.serviceMonitors.extraMetricProcessingRules | string | `""` | Extra metric processing rules for ServiceMonitors (Alloy relabel config syntax). Use this to filter/transform metrics after scraping. |
| prometheusOperatorObjects.serviceMonitors.labelExpressions | list | `[]` | Label expressions to filter which ServiceMonitors to scrape. Empty by default (scrape all). Example to exclude kube-state-metrics:   - key: "app.kubernetes.io/name"     operator: "NotIn"     values:       - "kube-state-metrics" |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
