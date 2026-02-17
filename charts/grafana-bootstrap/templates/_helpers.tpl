{{/*
Require environmentConfig.resourcePrefix to be set
*/}}
{{- define "grafana-bootstrap.resourcePrefix" -}}
{{- required "environmentConfig.resourcePrefix is required" .Values.environmentConfig.resourcePrefix -}}
{{- end -}}
