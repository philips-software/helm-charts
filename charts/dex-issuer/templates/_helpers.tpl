{{/*
Expand the name of the chart.
*/}}
{{- define "dex-issuer.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "dex-issuer.fullname" -}}
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
{{- define "dex-issuer.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "dex-issuer.labels" -}}
helm.sh/chart: {{ include "dex-issuer.chart" . }}
{{ include "dex-issuer.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "dex-issuer.selectorLabels" -}}
app.kubernetes.io/name: {{ include "dex-issuer.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Get the FQDN to use for the issuer.
Uses customFqdn when useCustomFqdn is true, otherwise uses clusterFqdn.
*/}}
{{- define "dex-issuer.fqdn" -}}
{{- if and .Values.useCustomFqdn .Values.environmentConfig.customFqdn }}
{{- .Values.environmentConfig.customFqdn }}
{{- else }}
{{- .Values.environmentConfig.clusterFqdn }}
{{- end }}
{{- end }}

{{/*
Generate the issuer host (without protocol).
*/}}
{{- define "dex-issuer.host" -}}
{{- if .Values.dex.httpRoute.enabled }}
{{- printf "%s.%s" .Values.dex.httpRoute.host (include "dex-issuer.fqdn" .) }}
{{- else }}
{{- printf "%s.%s" .Values.dex.ingress.host (include "dex-issuer.fqdn" .) }}
{{- end }}
{{- end }}

{{/*
Generate the public issuer URL (external).
*/}}
{{- define "dex-issuer.url" -}}
{{- printf "https://%s" (include "dex-issuer.host" .) }}
{{- end }}

{{/*
Generate the in-cluster Dex gRPC endpoint (host:port) used by provider-dex.
*/}}
{{- define "dex-issuer.grpcEndpoint" -}}
{{- printf "%s.%s.svc.cluster.local:5557" .Values.dexChart.releaseName .Release.Namespace }}
{{- end }}

{{/*
Validate required configuration values.
*/}}
{{- define "dex-issuer.validateConfig" -}}
{{- if not .Values.environmentConfig.clusterFqdn }}
{{- fail "environmentConfig.clusterFqdn is required and cannot be empty" }}
{{- end }}
{{- if not (regexMatch "^[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$" .Values.environmentConfig.clusterFqdn) }}
{{- fail "environmentConfig.clusterFqdn must be a valid domain name (e.g., example.com)" }}
{{- end }}
{{- if not .Values.environmentConfig.resourcePrefix }}
{{- fail "environmentConfig.resourcePrefix is required and cannot be empty" }}
{{- end }}
{{- if not (regexMatch "^[a-zA-Z0-9-]+$" .Values.environmentConfig.resourcePrefix) }}
{{- fail "environmentConfig.resourcePrefix must contain only alphanumeric characters and hyphens" }}
{{- end }}
{{- if not .Values.argocd.project }}
{{- fail "argocd.project is required and cannot be empty" }}
{{- end }}
{{- if not .Values.dexChart.version }}
{{- fail "dexChart.version is required and cannot be empty" }}
{{- end }}
{{- if .Values.dex.replicas }}
{{- if not (kindIs "float64" .Values.dex.replicas) }}
{{- fail "dex.replicas must be a number" }}
{{- end }}
{{- if lt (.Values.dex.replicas | int) 1 }}
{{- fail "dex.replicas must be at least 1" }}
{{- end }}
{{- end }}
{{- if and .Values.dex.ingress.enabled .Values.dex.httpRoute.enabled }}
{{- fail "dex.ingress and dex.httpRoute are mutually exclusive. Please enable only one of them." }}
{{- end }}
{{- end }}
