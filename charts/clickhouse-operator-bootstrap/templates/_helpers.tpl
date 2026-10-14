{{/*
Expand the name of the chart.
*/}}
{{- define "clickhouse-operator-bootstrap.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "clickhouse-operator-bootstrap.fullname" -}}
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
{{- define "clickhouse-operator-bootstrap.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "clickhouse-operator-bootstrap.labels" -}}
helm.sh/chart: {{ include "clickhouse-operator-bootstrap.chart" . }}
{{ include "clickhouse-operator-bootstrap.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "clickhouse-operator-bootstrap.selectorLabels" -}}
app.kubernetes.io/name: {{ include "clickhouse-operator-bootstrap.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Validate required configuration values
*/}}
{{- define "clickhouse-operator-bootstrap.validateConfig" -}}
{{- if not .Values.argoProject }}
{{- fail "argoProject is required and cannot be empty" }}
{{- end }}
{{- if not .Values.clickhouseOperatorChart.version }}
{{- fail "clickhouseOperatorChart.version is required and cannot be empty" }}
{{- end }}
{{- if not .Values.operator.namespace }}
{{- fail "operator.namespace is required and cannot be empty" }}
{{- end }}
{{- end }}
