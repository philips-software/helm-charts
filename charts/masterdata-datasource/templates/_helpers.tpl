{{/*
Expand the resource prefix.
*/}}
{{- define "masterdata-datasource.resourcePrefix" -}}
{{- required "A valid environmentConfig.resourcePrefix entry required!" .Values.environmentConfig.resourcePrefix -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "masterdata-datasource.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
