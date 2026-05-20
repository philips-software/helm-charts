# k8s-observability-monitoring v4.x Migration Design

## Overview

Migrate the k8s-observability-monitoring wrapper chart from k8s-monitoring v3.x to v4.x. This is a **breaking change** that restructures the values.yaml to align with upstream v4.x conventions while preserving the customAlloy functionality.

## Decisions

- **Deployment model**: Keep ArgoCD Application wrapper pattern
- **customAlloy**: Preserve existing pattern for dedicated kube-state-metrics scraping
- **Compatibility**: Breaking change (clean slate) - users must update values files
- **Pod logs**: Use `podLogsViaLoki` format
- **Version**: Bump to 1.0.0 to signal breaking changes

## Chart Metadata Changes

### Chart.yaml

```yaml
apiVersion: v2
name: k8s-observability-monitoring
version: 1.0.0
description: Helm chart for k8s-observability-monitoring

# renovate: datasource=helm depName=k8s-monitoring registryUrl=https://grafana.github.io/helm-charts
appVersion: "4.1.3"
```

## Values.yaml Restructuring

### Destinations (Breaking Change)

**Before (v3.x)**:
```yaml
otlp:
  destinations:
    - name: "otlpGateway"
      url: "https://otlp-gateway.example.com"
      secret:
        name: "otlp-gateway-creds"
        namespace: ""
      noAuth: false
      processors:
        batch:
          enabled: true
          size: 2000
      sendingQueue:
        enabled: true
        queueSize: 100
```

**After (v4.x)**:
```yaml
destinations:
  otlpGateway:
    type: otlp
    url: "https://otlp-gateway.example.com"
    protocol: http
    auth:
      type: basic
      usernameKey: "username"
      passwordKey: "apiKey"
    secret:
      create: false
      name: "otlp-gateway-creds"
      namespace: ""
    metrics:
      enabled: true
    logs:
      enabled: true
    traces:
      enabled: true
    processors:
      batch:
        enabled: true
        size: 2000
    sendingQueue:
      enabled: true
      queueSize: 100
```

**Key changes**:
- Array to map (name becomes the key)
- Explicit `type: otlp` and `protocol: http`
- Explicit `auth.type` (none, basic, bearerToken, oauth2, sigv4)
- Per-signal enable/disable

### SPIFFE Authentication

```yaml
destinations:
  spiffeDestination:
    type: otlp
    url: "https://otlp-gateway.example.com"
    protocol: http
    auth:
      type: bearerToken
      bearerTokenFile: "/var/run/secrets/spiffe/jwt/token"
```

The SPIFFE helper container configuration remains in `spiffe.*` but maps to bearerToken auth.

### Features (Breaking Change)

**Before (v3.x)**:
```yaml
features:
  autoInstrumentation: false
  prometheusOperatorObjects: true
  clusterMetrics: false
  applicationObservability: false
```

**After (v4.x)**:
```yaml
prometheusOperatorObjects:
  enabled: true
  destinations: []

clusterMetrics:
  enabled: false
  destinations: []

podLogsViaLoki:
  enabled: true
  destinations: []

applicationObservability:
  enabled: false
  destinations: []

autoInstrumentation:
  enabled: false
  destinations: []
```

### Prometheus Operator Objects

**Before**:
```yaml
prometheusOperatorObjects:
  serviceMonitors:
    labelExpressions: []
    extraDiscoveryRules: ""
    extraMetricProcessingRules: ""
    dropHighCardinalityMetrics:
      apiserverRequestDurationBuckets: false
      etcdRequestDurationBuckets: false
      apiserverRequestSliDurationBuckets: false
```

**After**:
```yaml
prometheusOperatorObjects:
  enabled: true
  destinations: []
  serviceMonitors:
    labelExpressions: []
    extraDiscoveryRules: ""
    extraMetricProcessingRules: ""
    metricsTuning:
      excludeMetrics: []
  # dropHighCardinalityMetrics removed - use metricsTuning.excludeMetrics instead
  # Example: excludeMetrics: ["apiserver_request_duration_seconds_bucket"]
```

### Pod Logs

**Before**:
```yaml
podLogs:
  dropKubeProbe: false
  excludeNamespaces: []
```

**After**:
```yaml
podLogsViaLoki:
  enabled: true
  destinations: []
  dropKubeProbe: false
  excludeNamespaces: []
```

The template will generate appropriate `extraLogProcessingStages` for these options.

### Cluster Metrics

**Before**:
```yaml
clusterMetrics:
  kubeStateMetrics:
    enabled: true
    deploy: false
    namespace: ""
    labelMatchers:
      app.kubernetes.io/name: kube-state-metrics
    useDefaultAllowList: false
    extraMetricProcessingRules: ""
  nodeExporter:
    enabled: true
    deploy: false
  kubelet:
    enabled: true
    nodeAddressFormat: direct
    useDefaultAllowList: true
  kubeletResource:
    enabled: true
    nodeAddressFormat: direct
```

**After**:
```yaml
clusterMetrics:
  enabled: false
  destinations: []
  kubelet:
    enabled: true
    nodeAddressFormat: direct
    metricsTuning:
      useDefaultAllowList: true
  kubeletResource:
    enabled: true
    nodeAddressFormat: direct

telemetryServices:
  kube-state-metrics:
    deploy: false
  node-exporter:
    deploy: false
```

Note: kube-state-metrics scraping is handled by customAlloy when enabled.

### Alloy Resources

**Before**:
```yaml
alloyLogs:
  resources:
    requests:
      cpu: 50m
      memory: 100Mi
    limits:
      memory: 200Mi

alloyMetrics:
  resources:
    requests:
      cpu: 300m
      memory: 1536Mi
    limits:
      memory: 3Gi
```

**After**:
```yaml
collectorCommon:
  alloy:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        memory: 512Mi
```

Note: `collectorCommon` applies to all Alloy collectors managed by the Alloy Operator. If per-collector resources are needed, define custom collectors in the `collectors:` map. For this migration, we'll use `collectorCommon` as a reasonable default since v4.x manages collector resources differently than v3.x's explicit alloy-logs/alloy-metrics sections.

### customAlloy (Preserved)

The `customAlloy` section remains unchanged as a custom extension:

```yaml
customAlloy:
  enabled: false
  replaceUpstreamCollector: false
  replicas: 1
  clustering:
    enabled: false
  liveDebugging:
    enabled: true
  sendingQueue:
    enabled: true
    queueSize: 500
    numConsumers: 10
  attributeCleanup:
    enabled: true
  attributePromotion:
    enabled: false
  kubeStateMetrics:
    extraMetricProcessingRules: ""
  kubelet:
    enabled: false
  resources:
    requests:
      cpu: 100m
      memory: 512Mi
    limits:
      memory: 1Gi
  vpa:
    enabled: false
    updateMode: "InPlaceOrRecreate"
    minAllowed:
      memory: 512Mi
    maxAllowed:
      memory: 8Gi
```

### Kyverno (Unchanged)

```yaml
kyverno:
  policyException:
    enabled: false
    policyName: "enforce-baseline-pod-security-profile"
    ruleNames:
      - "enforce-baseline-profile"
```

## Template Changes

### k8s-monitoring.yaml

No changes needed - continues to render ArgoCD Application.

### config/k8s-monitoring-values.yaml.tpl

Major rewrite to generate v4.x format:

1. **Destinations**: Iterate over map, generate v4.x destination config
2. **Features**: Generate individual feature blocks with destinations routing
3. **podLogsViaLoki**: Generate with extraLogProcessingStages for dropKubeProbe/excludeNamespaces
4. **clusterMetrics**: Generate with kubelet/kubeletResource config
5. **telemetryServices**: Generate kube-state-metrics and node-exporter deploy flags
6. **collectorCommon**: Generate from alloyMetrics/alloyLogs resources
7. **alloy-operator**: Keep deployment enabled

### custom-alloy-configmap.yaml

Update OTEL exporter configuration to match v4.x destination format when reading secrets.

## Migration Guide

### For Users

1. Update `otlp.destinations[]` array to `destinations:` map
2. Update `features.X` to top-level `X.enabled` blocks
3. Replace `podLogs.*` with `podLogsViaLoki.*`
4. Replace `clusterMetrics.kubeStateMetrics.useDefaultAllowList: false` with `metricsTuning`
5. Move `alloyLogs.resources` and `alloyMetrics.resources` to `collectorCommon.alloy.resources`

### Example Migration

**Before**:
```yaml
clusterName: "my-cluster"
otlp:
  destinations:
    - name: "grafanaCloud"
      url: "https://otlp-gateway.grafana.net"
      secret:
        name: "grafana-cloud-creds"
features:
  prometheusOperatorObjects: true
  clusterMetrics: false
podLogs:
  dropKubeProbe: true
```

**After**:
```yaml
clusterName: "my-cluster"
destinations:
  grafanaCloud:
    type: otlp
    url: "https://otlp-gateway.grafana.net"
    protocol: http
    auth:
      type: basic
      usernameKey: "username"
      passwordKey: "apiKey"
    secret:
      create: false
      name: "grafana-cloud-creds"
prometheusOperatorObjects:
  enabled: true
clusterMetrics:
  enabled: false
podLogsViaLoki:
  enabled: true
  dropKubeProbe: true
```

## Files to Modify

1. `Chart.yaml` - Version bump to 1.0.0, appVersion to 4.1.3
2. `values.yaml` - Complete restructure to v4.x format
3. `config/k8s-monitoring-values.yaml.tpl` - Rewrite for v4.x value generation
4. `templates/custom-alloy-configmap.yaml` - Update destination references
5. `README.md` / `README.md.gotmpl` - Update documentation

## Testing Plan

1. Render templates with `helm template` and verify v4.x output format
2. Deploy to homelab cluster and verify:
   - Metrics collection (customAlloy kube-state-metrics)
   - Log collection (podLogsViaLoki)
   - OTLP destination connectivity
3. Verify no duplicate job labels (the bug fix must still work)
4. Test SPIFFE authentication if available

## Risks

1. **Breaking change scope**: All existing users must update values files
2. **customAlloy compatibility**: May need adjustments for v4.x collector interactions
3. **Alloy Operator**: v4.x uses Alloy Operator which adds new CRDs

## Timeline

1. Update values.yaml schema
2. Rewrite k8s-monitoring-values.yaml.tpl
3. Update custom-alloy templates
4. Test in homelab
5. Update documentation
6. Release 1.0.0
