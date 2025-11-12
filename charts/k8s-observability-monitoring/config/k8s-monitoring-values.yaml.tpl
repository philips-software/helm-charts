cluster:
  name: {{ .Values.clusterName }}

{{- if or .Values.otlp.keepTopDestination .Values.otlp.destinations }}
destinations:
{{- if .Values.otlp.keepTopDestination }}
  - name: oltpGateway
    protocol: http
    type: otlp
    url: {{ .Values.otlp.gateway }}
    auth:
      type: basic
      usernameKey: "username"
      passwordKey: "apiKey"
    secret:
      create: false
      name: {{ .Values.otlp.secret.name }}
      namespace: {{ .Release.Namespace }}
    logs:
      enabled: true
    metrics:
      enabled: true
    traces:
      enabled: true
{{- end }}
{{- range .Values.otlp.destinations }}
  # destination: {{ .name }}
  - name: {{ .name }}
    protocol: http
    type: otlp
    url: {{ .url }}
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
{{- end }}
{{- else }}
destinations: []
{{- end }}

applicationObservability:
  enabled: true
  receivers:
    otlp:
      enabled: true
      http:
        enabled: true
      grpc:
        enabled: true

prometheusOperatorObjects:
  enabled: true

podLogs:
  enabled: true

traces:
  enabled: true

autoInstrumentation:
  enabled: {{ .Values.features.autoInstrumentation }}

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
        cpu: 500m
  controller:
    resources:
      requests:
        memory: 5Mi
        cpu: 1m
      limits:
        memory: 10Mi
        cpu: 10m

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
    resources:
      requests:
        memory: 5Mi
        cpu: 1m
      limits:
        memory: 10Mi
        cpu: 10m
    affinity:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
            - matchExpressions:
                - key: eks.amazonaws.com/compute-type
                  operator: NotIn
                  values:
                    - fargate

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
  controller:
    resources:
      requests:
        memory: 5Mi
        cpu: 1m
      limits:
        memory: 10Mi
        cpu: 10m