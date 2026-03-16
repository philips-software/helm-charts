{{/*
Validate clusterName is set to a non-empty value.
Usage: {{ include "k8s-monitoring.validateClusterName" . }}
*/}}
{{- define "k8s-monitoring.validateClusterName" -}}
  {{- if not (or .Values.clusterName (ne .Values.clusterName "")) -}}
    {{- fail "clusterName must be set to a non-empty value at install time (e.g., --set clusterName=my-cluster)" -}}
  {{- end }}
{{- end }}
