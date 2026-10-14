{{/*
Expand the name of the chart.
*/}}
{{- define "zitadel-bootstrap.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "zitadel-bootstrap.fullname" -}}
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
{{- define "zitadel-bootstrap.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "zitadel-bootstrap.labels" -}}
helm.sh/chart: {{ include "zitadel-bootstrap.chart" . }}
{{ include "zitadel-bootstrap.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "zitadel-bootstrap.selectorLabels" -}}
app.kubernetes.io/name: {{ include "zitadel-bootstrap.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
CNPG Cluster resource name
*/}}
{{- define "zitadel-bootstrap.postgresClusterName" -}}
{{- .Values.database.clusterName | default "zitadel-db" -}}
{{- end }}

{{/*
Public hostname when ingress.httpRoute.enabled is true.
*/}}
{{- define "zitadel-bootstrap.host" -}}
{{- printf "%s.%s" .Values.ingress.httpRoute.host .Values.environmentConfig.clusterFqdn -}}
{{- end }}

{{/*
Validate required configuration values
*/}}
{{- define "zitadel-bootstrap.validateConfig" -}}
{{- if not .Values.argoProject }}
{{- fail "argoProject is required and cannot be empty" }}
{{- end }}
{{- if not .Values.zitadelChart.version }}
{{- fail "zitadelChart.version is required and cannot be empty" }}
{{- end }}
{{- if .Values.ingress.httpRoute.enabled }}
{{- if not .Values.environmentConfig.clusterFqdn }}
{{- fail "environmentConfig.clusterFqdn is required when ingress.httpRoute.enabled is true" }}
{{- end }}
{{- end }}
{{- if not .Values.credentials.masterkey }}
{{- fail "credentials.masterkey is required and cannot be empty" }}
{{- end }}
{{- if ne (len .Values.credentials.masterkey) 32 }}
{{- fail (printf "credentials.masterkey must be exactly 32 bytes, got %d" (len .Values.credentials.masterkey)) }}
{{- end }}
{{- if not .Values.credentials.postgresPassword }}
{{- fail "credentials.postgresPassword is required and cannot be empty" }}
{{- end }}
{{- if not .Values.credentials.adminUsername }}
{{- fail "credentials.adminUsername is required and cannot be empty" }}
{{- end }}
{{- if not .Values.credentials.adminPassword }}
{{- fail "credentials.adminPassword is required and cannot be empty" }}
{{- end }}
{{- end }}
