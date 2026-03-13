cluster:
  name: {{ .Values.clusterName }}

{{- if .Values.otlp.destinations }}
destinations:
{{- range .Values.otlp.destinations }}
{{- if .secret }}
  # destination: {{ .name }}
  - name: {{ .name }}
    type: otlp
    url: {{ .url }}
    protocol: http
    {{- if not .noAuth }}
    auth:
      type: basic
      usernameKey: "username"
      passwordKey: "apiKey"
    {{- end }}
    secret:
      create: false
      name: {{ .secret.name }}
      namespace: {{ default $.Release.Namespace .secret.namespace }}
    logs:
      enabled: true
    metrics:
      enabled: true
    traces:
      enabled: true
    {{- if .processors }}
    processors:
      {{- if .processors.batch }}
      batch:
        enabled: {{ default true .processors.batch.enabled }}
        {{- if .processors.batch.size }}
        size: {{ .processors.batch.size }}
        {{- end }}
        {{- if .processors.batch.maxSize }}
        maxSize: {{ .processors.batch.maxSize }}
        {{- end }}
      {{- end }}
    {{- end }}
    {{- if .sendingQueue }}
    sendingQueue:
      enabled: {{ default true .sendingQueue.enabled }}
      {{- if .sendingQueue.queueSize }}
      queueSize: {{ .sendingQueue.queueSize }}
      {{- end }}
      {{- if .sendingQueue.numConsumers }}
      numConsumers: {{ .sendingQueue.numConsumers }}
      {{- end }}
    {{- end }}
{{- end }}
{{- end }}
{{- else }}
destinations: []
{{- end }}

# Alloy Operator - manages Alloy CRDs (required in v3.x)
alloy-operator:
  deploy: true
  waitForAlloyRemoval:
    enabled: true
    nodeSelector:
      kubernetes.io/os: linux

applicationObservability:
  enabled: true
  receivers:
    otlp:
      grpc:
        enabled: true
        port: 4317
      http:
        enabled: true
        port: 4318

prometheusOperatorObjects:
  # Disabled when customAlloy.replaceUpstreamCollector is true (customAlloy handles it)
  enabled: {{ if and .Values.customAlloy .Values.customAlloy.enabled .Values.customAlloy.replaceUpstreamCollector }}false{{ else }}{{ .Values.features.prometheusOperatorObjects }}{{ end }}
  {{- if and .Values.features.prometheusOperatorObjects (not (and .Values.customAlloy .Values.customAlloy.enabled .Values.customAlloy.replaceUpstreamCollector)) }}
  serviceMonitors:
    {{- /* Collect all label expressions */ -}}
    {{- $labelExpressions := list }}
    {{- if and .Values.prometheusOperatorObjects .Values.prometheusOperatorObjects.serviceMonitors .Values.prometheusOperatorObjects.serviceMonitors.labelExpressions }}
    {{- $labelExpressions = .Values.prometheusOperatorObjects.serviceMonitors.labelExpressions }}
    {{- end }}
    {{- /* When customAlloy is enabled, exclude kube-state-metrics from ServiceMonitor scraping */ -}}
    {{- if and .Values.customAlloy .Values.customAlloy.enabled }}
    {{- $ksmExclusion := dict "key" "app.kubernetes.io/name" "operator" "NotIn" "values" (list "kube-state-metrics") }}
    {{- $labelExpressions = append $labelExpressions $ksmExclusion }}
    {{- end }}
    {{- if gt (len $labelExpressions) 0 }}
    labelExpressions:
      {{- toYaml $labelExpressions | nindent 6 }}
    {{- end }}
    {{- if and .Values.prometheusOperatorObjects .Values.prometheusOperatorObjects.serviceMonitors .Values.prometheusOperatorObjects.serviceMonitors.extraDiscoveryRules }}
    extraDiscoveryRules: |
{{ .Values.prometheusOperatorObjects.serviceMonitors.extraDiscoveryRules | indent 6 }}
    {{- end }}
    {{- if and .Values.prometheusOperatorObjects .Values.prometheusOperatorObjects.serviceMonitors .Values.prometheusOperatorObjects.serviceMonitors.extraMetricProcessingRules }}
    extraMetricProcessingRules: |
{{ .Values.prometheusOperatorObjects.serviceMonitors.extraMetricProcessingRules | indent 6 }}
    {{- end }}
  {{- end }}

# Cluster metrics - built-in kube-state-metrics and node-exporter scraping
clusterMetrics:
  enabled: {{ .Values.features.clusterMetrics }}
  {{- if and .Values.features.clusterMetrics .Values.clusterMetrics }}
  {{- with .Values.clusterMetrics }}
  kube-state-metrics:
    {{- /* Disable kube-state-metrics in k8s-monitoring when customAlloy is enabled */ -}}
    {{- if and $.Values.customAlloy $.Values.customAlloy.enabled }}
    enabled: false
    {{- else }}
    enabled: {{ default true .kubeStateMetrics.enabled }}
    {{- end }}
    deploy: {{ default false .kubeStateMetrics.deploy }}
    {{- if .kubeStateMetrics.namespace }}
    namespace: {{ .kubeStateMetrics.namespace }}
    {{- end }}
    {{- if .kubeStateMetrics.labelMatchers }}
    labelMatchers:
      {{- toYaml .kubeStateMetrics.labelMatchers | nindent 6 }}
    {{- end }}
    metricsTuning:
      useDefaultAllowList: {{ default false .kubeStateMetrics.useDefaultAllowList }}
    {{- if .kubeStateMetrics.extraMetricProcessingRules }}
    extraMetricProcessingRules: |
{{ .kubeStateMetrics.extraMetricProcessingRules | indent 6 }}
    {{- end }}
  node-exporter:
    enabled: {{ default true .nodeExporter.enabled }}
    deploy: {{ default false .nodeExporter.deploy }}
  {{- end }}
  {{- end }}

podLogs:
  enabled: true

autoInstrumentation:
  enabled: {{ .Values.features.autoInstrumentation }}

# Enable the metrics collector
# Disabled when customAlloy.replaceUpstreamCollector is true
alloy-metrics:
  enabled: {{ if and .Values.customAlloy .Values.customAlloy.enabled .Values.customAlloy.replaceUpstreamCollector }}false{{ else }}true{{ end }}
  liveDebugging:
    enabled: true
  alloy:
    stabilityLevel: experimental
    resources:
      requests:
        memory: 1536Mi
        cpu: 300m
      limits:
        memory: 3Gi
        cpu: 600m

# Enable the logs collector
alloy-logs:
  enabled: true
  liveDebugging:
    enabled: true
  alloy:
    stabilityLevel: experimental
    resources:
      requests:
        memory: 100Mi
        cpu: 100m
      limits:
        memory: 200Mi
        cpu: 200m
  controller:
    affinity:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
            - matchExpressions:
                - key: eks.amazonaws.com/compute-type
                  operator: NotIn
                  values:
                    - fargate

# Enable the receiver for application telemetry
alloy-receiver:
  enabled: true
  alloy:
    resources:
      requests:
        memory: 100Mi
        cpu: 100m
      limits:
        memory: 200Mi
        cpu: 200m
    extraPorts:
      - name: otlp-grpc
        port: 4317
        targetPort: 4317
        protocol: TCP
      - name: otlp-http
        port: 4318
        targetPort: 4318
        protocol: TCP
