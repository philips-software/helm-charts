cluster:
  name: {{ .Values.clusterName }}

{{- if .Values.otlp.destinations }}
destinations:
{{- range .Values.otlp.destinations }}
  # destination: {{ .name }}
  - name: {{ .name }}
    type: otlp
    url: {{ .url }}
    protocol: http
    auth:
      type: basic
      usernameKey: "username"
      passwordKey: "apiKey"
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
  enabled: {{ .Values.features.prometheusOperatorObjects }}
  {{- with .Values.prometheusOperatorObjects.serviceMonitors }}
  {{- if or .extraDiscoveryRules .extraMetricProcessingRules }}
  serviceMonitors:
    {{- if .extraDiscoveryRules }}
    extraDiscoveryRules: |
{{ .extraDiscoveryRules | indent 6 }}
    {{- end }}
    {{- if .extraMetricProcessingRules }}
    extraMetricProcessingRules: |
{{ .extraMetricProcessingRules | indent 6 }}
    {{- end }}
  {{- end }}
  {{- end }}

podLogs:
  enabled: true

autoInstrumentation:
  enabled: {{ .Values.features.autoInstrumentation }}

# Enable the metrics collector
alloy-metrics:
  enabled: true
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
