cluster:
  name: {{ .Values.clusterName }}

{{- if .Values.destinations }}
destinations:
{{- range $name, $dest := .Values.destinations }}
{{- if not $dest.customAlloyOnly }}
  {{ $name }}:
    type: {{ $dest.type | default "otlp" }}
    url: {{ $dest.url }}
    {{- if $dest.protocol }}
    protocol: {{ $dest.protocol }}
    {{- end }}
    {{- if $dest.auth }}
    auth:
      type: {{ $dest.auth.type | default "none" }}
      {{- if eq $dest.auth.type "basic" }}
      usernameKey: {{ $dest.auth.usernameKey | default "username" | quote }}
      passwordKey: {{ $dest.auth.passwordKey | default "apiKey" | quote }}
      {{- end }}
      {{- if eq $dest.auth.type "bearerToken" }}
      {{- if $dest.auth.bearerTokenFile }}
      bearerTokenFile: {{ $dest.auth.bearerTokenFile | quote }}
      {{- end }}
      {{- end }}
    {{- end }}
    {{- if $dest.secret }}
    secret:
      create: {{ $dest.secret.create | default false }}
      name: {{ $dest.secret.name }}
      {{- if $dest.secret.namespace }}
      namespace: {{ $dest.secret.namespace }}
      {{- end }}
    {{- end }}
    {{- if hasKey $dest "metrics" }}
    metrics:
      enabled: {{ $dest.metrics.enabled }}
    {{- end }}
    {{- if hasKey $dest "logs" }}
    logs:
      enabled: {{ $dest.logs.enabled }}
    {{- end }}
    {{- if hasKey $dest "traces" }}
    traces:
      enabled: {{ $dest.traces.enabled }}
    {{- end }}
    {{- if $dest.processors }}
    processors:
      {{- toYaml $dest.processors | nindent 6 }}
    {{- end }}
    {{- if $dest.sendingQueue }}
    sendingQueue:
      {{- toYaml $dest.sendingQueue | nindent 6 }}
    {{- end }}
{{- end }}
{{- end }}
{{- else }}
destinations: {}
{{- end }}

# Collectors
collectors:
  {{- $needsMetricsCollector := or (and .Values.prometheusOperatorObjects.enabled (not (and .Values.customAlloy .Values.customAlloy.enabled .Values.customAlloy.replaceUpstreamCollector))) .Values.clusterMetrics.enabled }}
  {{- if $needsMetricsCollector }}
  alloy-metrics:
    presets: [clustered, statefulset, medium]
    {{- if index .Values.collectors "alloy-metrics" }}
    {{- toYaml (index .Values.collectors "alloy-metrics") | nindent 4 }}
    {{- end }}
  {{- end }}
  alloy-logs:
    presets: [small, filesystem-log-reader, daemonset]
    {{- if index .Values.collectors "alloy-logs" }}
    {{- toYaml (index .Values.collectors "alloy-logs") | nindent 4 }}
    {{- end }}
  {{- if .Values.applicationObservability.enabled }}
  alloy-receiver:
    presets: [small, deployment]
    {{- if index .Values.collectors "alloy-receiver" }}
    {{- toYaml (index .Values.collectors "alloy-receiver") | nindent 4 }}
    {{- end }}
  {{- end }}

# Alloy Operator
alloy-operator:
  deploy: true
  waitForAlloyRemoval:
    enabled: true
    nodeSelector:
      kubernetes.io/os: linux

# Prometheus Operator Objects
prometheusOperatorObjects:
  {{- if and .Values.customAlloy .Values.customAlloy.enabled .Values.customAlloy.replaceUpstreamCollector }}
  enabled: false
  {{- else }}
  enabled: {{ .Values.prometheusOperatorObjects.enabled }}
  collector: alloy-metrics
  {{- end }}
  {{- if .Values.prometheusOperatorObjects.destinations }}
  destinations: {{ toYaml .Values.prometheusOperatorObjects.destinations | nindent 4 }}
  {{- end }}
  {{- if .Values.prometheusOperatorObjects.serviceMonitors }}
  serviceMonitors:
    {{- $labelExpressions := list }}
    {{- if .Values.prometheusOperatorObjects.serviceMonitors.labelExpressions }}
    {{- $labelExpressions = .Values.prometheusOperatorObjects.serviceMonitors.labelExpressions }}
    {{- end }}
    {{- if and .Values.customAlloy .Values.customAlloy.enabled }}
    {{- $ksmExclusion := dict "key" "app.kubernetes.io/name" "operator" "NotIn" "values" (list "kube-state-metrics") }}
    {{- $labelExpressions = append $labelExpressions $ksmExclusion }}
    {{- end }}
    {{- if gt (len $labelExpressions) 0 }}
    labelExpressions:
      {{- toYaml $labelExpressions | nindent 6 }}
    {{- end }}
    {{- if .Values.prometheusOperatorObjects.serviceMonitors.extraDiscoveryRules }}
    extraDiscoveryRules: |
{{ .Values.prometheusOperatorObjects.serviceMonitors.extraDiscoveryRules | indent 6 }}
    {{- end }}
    {{- if .Values.prometheusOperatorObjects.serviceMonitors.extraMetricProcessingRules }}
    extraMetricProcessingRules: |
{{ .Values.prometheusOperatorObjects.serviceMonitors.extraMetricProcessingRules | indent 6 }}
    {{- end }}
    {{- if .Values.prometheusOperatorObjects.serviceMonitors.metricsTuning }}
    metricsTuning:
      {{- toYaml .Values.prometheusOperatorObjects.serviceMonitors.metricsTuning | nindent 6 }}
    {{- end }}
  {{- end }}

# Cluster Metrics
clusterMetrics:
  enabled: {{ .Values.clusterMetrics.enabled }}
  collector: alloy-metrics
  {{- if .Values.clusterMetrics.destinations }}
  destinations: {{ toYaml .Values.clusterMetrics.destinations | nindent 4 }}
  {{- end }}
  {{- if .Values.clusterMetrics.kubelet }}
  kubelet:
    {{- if and .Values.customAlloy .Values.customAlloy.enabled .Values.customAlloy.kubelet.enabled }}
    enabled: false
    {{- else }}
    enabled: {{ .Values.clusterMetrics.kubelet.enabled }}
    {{- end }}
    {{- if .Values.clusterMetrics.kubelet.nodeAddressFormat }}
    nodeAddressFormat: {{ .Values.clusterMetrics.kubelet.nodeAddressFormat }}
    {{- end }}
    {{- if .Values.clusterMetrics.kubelet.metricsTuning }}
    metricsTuning:
      {{- toYaml .Values.clusterMetrics.kubelet.metricsTuning | nindent 6 }}
    {{- end }}
  {{- end }}
  {{- if .Values.clusterMetrics.kubeletResource }}
  kubeletResource:
    {{- if and .Values.customAlloy .Values.customAlloy.enabled .Values.customAlloy.kubelet.enabled }}
    enabled: false
    {{- else }}
    enabled: {{ .Values.clusterMetrics.kubeletResource.enabled }}
    {{- end }}
    {{- if .Values.clusterMetrics.kubeletResource.nodeAddressFormat }}
    nodeAddressFormat: {{ .Values.clusterMetrics.kubeletResource.nodeAddressFormat }}
    {{- end }}
  {{- end }}

# Pod Logs via Loki
podLogsViaLoki:
  enabled: {{ .Values.podLogsViaLoki.enabled }}
  collector: alloy-logs
  {{- if .Values.podLogsViaLoki.destinations }}
  destinations: {{ toYaml .Values.podLogsViaLoki.destinations | nindent 4 }}
  {{- end }}
  {{- $hasDropKubeProbe := .Values.podLogsViaLoki.dropKubeProbe }}
  {{- $hasExcludeNamespaces := and .Values.podLogsViaLoki.excludeNamespaces (gt (len .Values.podLogsViaLoki.excludeNamespaces) 0) }}
  {{- if or $hasDropKubeProbe $hasExcludeNamespaces }}
  extraLogProcessingStages: |
    {{- if $hasDropKubeProbe }}
    stage.drop {
      source = ""
      expression = "kube-probe/"
      drop_counter_reason = "kube-probe"
    }
    {{- end }}
    {{- if $hasExcludeNamespaces }}
    {{- range .Values.podLogsViaLoki.excludeNamespaces }}
    stage.match {
      selector = "{namespace=\"{{ . }}\"}"
      action = "drop"
      drop_counter_reason = "excluded-namespace"
    }
    {{- end }}
    {{- end }}
  {{- end }}

# Application Observability
applicationObservability:
  enabled: {{ .Values.applicationObservability.enabled }}
  {{- if .Values.applicationObservability.enabled }}
  collector: alloy-receiver
  {{- end }}
  {{- if .Values.applicationObservability.destinations }}
  destinations: {{ toYaml .Values.applicationObservability.destinations | nindent 4 }}
  {{- end }}
  {{- if .Values.applicationObservability.receivers }}
  receivers:
    {{- toYaml .Values.applicationObservability.receivers | nindent 4 }}
  {{- end }}

# Auto-instrumentation
autoInstrumentation:
  enabled: {{ .Values.autoInstrumentation.enabled }}

# Telemetry Services
telemetryServices:
  kube-state-metrics:
    deploy: {{ index .Values.telemetryServices "kube-state-metrics" "deploy" | default false }}
  node-exporter:
    deploy: {{ index .Values.telemetryServices "node-exporter" "deploy" | default false }}

# Collector Common
{{- if .Values.collectorCommon }}
collectorCommon:
  {{- toYaml .Values.collectorCommon | nindent 2 }}
{{- end }}
