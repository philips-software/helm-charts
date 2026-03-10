{{/*
Expand the name of the chart.
*/}}
{{- define "tempo-bootstrap.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "tempo-bootstrap.fullname" -}}
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
{{- define "tempo-bootstrap.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "tempo-bootstrap.labels" -}}
helm.sh/chart: {{ include "tempo-bootstrap.chart" . }}
{{ include "tempo-bootstrap.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "tempo-bootstrap.selectorLabels" -}}
app.kubernetes.io/name: {{ include "tempo-bootstrap.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Substitute variables in a string
Supports variables like ${resourcePrefix}, ${region}, etc.
Usage: include "tempo-bootstrap.substituteVars" dict "str" .Values.myValue "ctx" .
*/}}
{{- define "tempo-bootstrap.substituteVars" -}}
{{- $str := .str }}
{{- $ctx := .ctx }}
{{- if $ctx.Values.environmentConfig }}
{{- $str = $str | replace "${resourcePrefix}" $ctx.Values.environmentConfig.resourcePrefix }}
{{- $str = $str | replace "${region}" $ctx.Values.environmentConfig.region }}
{{- end }}
{{- $str }}
{{- end }}

{{/*
Validate required configuration values
*/}}
{{- define "tempo-bootstrap.validateConfig" -}}
{{- if not .Values.existingBucketName }}
{{- fail "existingBucketName is required and cannot be empty" }}
{{- end }}
{{- if not .Values.environmentConfig.resourcePrefix }}
{{- fail "environmentConfig.resourcePrefix is required and cannot be empty" }}
{{- end }}
{{- if not .Values.environmentConfig.region }}
{{- fail "environmentConfig.region is required and cannot be empty" }}
{{- end }}
{{- if not (regexMatch "^[a-z]{2}-[a-z]+-[0-9]+$" .Values.environmentConfig.region) }}
{{- fail "environmentConfig.region must be a valid AWS region format (e.g., us-east-1, eu-west-1)" }}
{{- end }}
{{- if not .Values.environmentConfig.accountId }}
{{- fail "environmentConfig.accountId is required and cannot be empty" }}
{{- end }}
{{- if not (regexMatch "^[0-9]{12}$" (printf "%v" .Values.environmentConfig.accountId)) }}
{{- fail "environmentConfig.accountId must be a 12-digit AWS account ID" }}
{{- end }}
{{- if not .Values.argoProject }}
{{- fail "argoProject is required and cannot be empty" }}
{{- end }}
{{- if not .Values.compactorOrgmapper.package }}
{{- fail "compactorOrgmapper.package is required and cannot be empty" }}
{{- end }}
{{- if not .Values.compactorOrgmapper.tag }}
{{- fail "compactorOrgmapper.tag is required and cannot be empty" }}
{{- end }}
{{- if not .Values.initOverrides.package }}
{{- fail "initOverrides.package is required and cannot be empty" }}
{{- end }}
{{- if not .Values.initOverrides.tag }}
{{- fail "initOverrides.tag is required and cannot be empty" }}
{{- end }}
{{- if not (kindIs "bool" .Values.multitenancyEnabled) }}
{{- fail "multitenancyEnabled must be a boolean (true or false)" }}
{{- end }}
{{- if not .Values.tempoChart.version }}
{{- fail "tempoChart.version is required and cannot be empty" }}
{{- end }}
{{- end }}