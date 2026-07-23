{{/*
Expand the name of the chart.
*/}}
{{- define "agentgateway-bootstrap.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "agentgateway-bootstrap.fullname" -}}
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
{{- define "agentgateway-bootstrap.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "agentgateway-bootstrap.labels" -}}
helm.sh/chart: {{ include "agentgateway-bootstrap.chart" . }}
{{ include "agentgateway-bootstrap.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "agentgateway-bootstrap.selectorLabels" -}}
app.kubernetes.io/name: {{ include "agentgateway-bootstrap.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Substitute variables in a string
Supports variables like ${resourcePrefix}, ${region}, ${accountId}
Usage: include "agentgateway-bootstrap.substituteVars" (dict "str" .Values.myValue "ctx" .)
*/}}
{{- define "agentgateway-bootstrap.substituteVars" -}}
{{- $str := .str }}
{{- $ctx := .ctx }}
{{- if $ctx.Values.environmentConfig }}
{{- if $ctx.Values.environmentConfig.resourcePrefix }}
{{- $str = $str | replace "${resourcePrefix}" $ctx.Values.environmentConfig.resourcePrefix }}
{{- end }}
{{- if $ctx.Values.environmentConfig.region }}
{{- $str = $str | replace "${region}" $ctx.Values.environmentConfig.region }}
{{- end }}
{{- if $ctx.Values.environmentConfig.accountId }}
{{- $str = $str | replace "${accountId}" (printf "%v" $ctx.Values.environmentConfig.accountId) }}
{{- end }}
{{- end }}
{{- $str }}
{{- end }}

{{/*
Validate required configuration values
*/}}
{{/*
Name of the CNPG Cluster provisioned for LLM cost tracking.
*/}}
{{- define "agentgateway-bootstrap.postgresClusterName" -}}
{{- .Values.database.clusterName | default (printf "%s-db" .Values.gateway.name) -}}
{{- end }}

{{- define "agentgateway-bootstrap.validateConfig" -}}
{{- if not .Values.argoProject }}
{{- fail "argoProject is required and cannot be empty" }}
{{- end }}
{{- if not .Values.agentgatewayCrdsChart.version }}
{{- fail "agentgatewayCrdsChart.version is required and cannot be empty" }}
{{- end }}
{{- if not .Values.agentgatewayChart.version }}
{{- fail "agentgatewayChart.version is required and cannot be empty" }}
{{- end }}
{{- end }}
