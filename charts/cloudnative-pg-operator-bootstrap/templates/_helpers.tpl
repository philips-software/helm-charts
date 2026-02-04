{{/*
Expand the name of the chart.
*/}}
{{- define "cloudnative-pg-operator-bootstrap.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "cloudnative-pg-operator-bootstrap.fullname" -}}
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
{{- define "cloudnative-pg-operator-bootstrap.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "cloudnative-pg-operator-bootstrap.labels" -}}
helm.sh/chart: {{ include "cloudnative-pg-operator-bootstrap.chart" . }}
{{ include "cloudnative-pg-operator-bootstrap.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "cloudnative-pg-operator-bootstrap.selectorLabels" -}}
app.kubernetes.io/name: {{ include "cloudnative-pg-operator-bootstrap.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Validate required configuration values
*/}}
{{- define "cloudnative-pg-operator-bootstrap.validateConfig" -}}
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
