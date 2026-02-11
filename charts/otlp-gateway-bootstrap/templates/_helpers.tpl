{{/*
Expand the name of the chart.
*/}}
{{- define "otlp-gateway-bootstrap.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "otlp-gateway-bootstrap.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "otlp-gateway-bootstrap.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "otlp-gateway-bootstrap.labels" -}}
helm.sh/chart: {{ include "otlp-gateway-bootstrap.chart" . }}
{{ include "otlp-gateway-bootstrap.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "otlp-gateway-bootstrap.selectorLabels" -}}
app.kubernetes.io/name: {{ include "otlp-gateway-bootstrap.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Validate required configuration values
*/}}
{{- define "otlp-gateway-bootstrap.validateConfig" -}}
{{- if not .Values.chartRepo.url }}
{{- fail "chartRepo.url is required and cannot be empty" }}
{{- end }}
{{- if not .Values.chartRepo.targetRevision }}
{{- fail "chartRepo.targetRevision is required and cannot be empty" }}
{{- end }}
{{- if not .Values.argoProject }}
{{- fail "argoProject is required and cannot be empty" }}
{{- end }}
{{- end }}
