{{/*
Expand the name of the chart.
*/}}
{{- define "cloudnative-pg-operator.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "cloudnative-pg-operator.fullname" -}}
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
{{- define "cloudnative-pg-operator.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "cloudnative-pg-operator.labels" -}}
helm.sh/chart: {{ include "cloudnative-pg-operator.chart" . }}
{{ include "cloudnative-pg-operator.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "cloudnative-pg-operator.selectorLabels" -}}
app.kubernetes.io/name: {{ include "cloudnative-pg-operator.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Substitute variables in a string
Supports variables like ${resourcePrefix}, ${sharedServicesAccountId}, ${region}, etc.
Usage: include "cloudnative-pg-operator.substituteVars" (dict "str" .Values.myValue "ctx" .)
*/}}
{{- define "cloudnative-pg-operator.substituteVars" -}}
{{- $str := .str }}
{{- $ctx := .ctx }}
{{- if $ctx.Values.environmentConfig }}
{{- $str = $str | replace "${resourcePrefix}" $ctx.Values.environmentConfig.resourcePrefix }}
{{- $str = $str | replace "${sharedServicesAccountId}" ($ctx.Values.environmentConfig.sharedServicesAccountId | toString) }}
{{- $str = $str | replace "${region}" $ctx.Values.environmentConfig.region }}
{{- end }}
{{- $str }}
{{- end }}

{{/*
Validate required configuration values
*/}}
{{- define "cloudnative-pg-operator.validateConfig" -}}
{{- if not .Values.environmentConfig.resourcePrefix }}
{{- fail "environmentConfig.resourcePrefix is required and cannot be empty" }}
{{- end }}
{{- if not .Values.environmentConfig.sharedServicesAccountId }}
{{- fail "environmentConfig.sharedServicesAccountId is required and cannot be empty" }}
{{- end }}
{{- if not .Values.environmentConfig.region }}
{{- fail "environmentConfig.region is required and cannot be empty" }}
{{- end }}
{{- if not .Values.argoProject }}
{{- fail "argoProject is required and cannot be empty" }}
{{- end }}
{{- if not .Values.cnpgChart.version }}
{{- fail "cnpgChart.version is required and cannot be empty" }}
{{- end }}
{{- if and .Values.kyvernoPolicy.enabled (not .Values.environmentConfig.sharedServicesAccountId) }}
{{- fail "environmentConfig.sharedServicesAccountId is required when kyvernoPolicy.enabled is true" }}
{{- end }}
{{- if and .Values.imageCatalog.enabled (not .Values.kyvernoPolicy.enabled) }}
{{- fail "kyvernoPolicy.enabled must be true when imageCatalog.enabled is true" }}
{{- end }}
{{- end }}
