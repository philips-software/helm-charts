{{/*
Expand the name of the chart.
*/}}
{{- define "langfuse-bootstrap.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "langfuse-bootstrap.fullname" -}}
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
{{- define "langfuse-bootstrap.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "langfuse-bootstrap.labels" -}}
helm.sh/chart: {{ include "langfuse-bootstrap.chart" . }}
{{ include "langfuse-bootstrap.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "langfuse-bootstrap.selectorLabels" -}}
app.kubernetes.io/name: {{ include "langfuse-bootstrap.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
CNPG Cluster resource name
*/}}
{{- define "langfuse-bootstrap.postgresClusterName" -}}
{{- .Values.database.clusterName | default "langfuse-db" -}}
{{- end }}

{{/*
ServiceAccount name shared by the S3IRSA CR and the langfuse chart's
langfuse.serviceAccount.name — must match exactly so the IRSA role binds to
the ServiceAccount the langfuse-web/langfuse-worker pods actually run as.
*/}}
{{- define "langfuse-bootstrap.s3ServiceAccountName" -}}
{{- if .Values.environmentConfig.resourcePrefix }}
{{- printf "%s-langfuse" .Values.environmentConfig.resourcePrefix | trunc 63 | trimSuffix "-" -}}
{{- else }}
{{- "langfuse" -}}
{{- end }}
{{- end }}

{{/*
Public hostname when ingress.httpRoute.enabled is true.
*/}}
{{- define "langfuse-bootstrap.host" -}}
{{- printf "%s.%s" .Values.ingress.httpRoute.host .Values.environmentConfig.clusterFqdn -}}
{{- end }}

{{/*
Canonical NextAuth URL: derived from the HTTPRoute host when enabled
(required for SSO's OAuth callback to land on a reachable URL), otherwise
langfuse.nextauthUrl (the port-forward-friendly default).
*/}}
{{- define "langfuse-bootstrap.nextauthUrl" -}}
{{- if .Values.ingress.httpRoute.enabled }}
{{- printf "https://%s" (include "langfuse-bootstrap.host" .) -}}
{{- else }}
{{- .Values.langfuse.nextauthUrl -}}
{{- end }}
{{- end }}

{{/*
Substitute variables in a string.
Supports ${resourcePrefix}, ${region}, ${accountId}.
Usage: include "langfuse-bootstrap.substituteVars" (dict "str" .Values.myValue "ctx" .)
*/}}
{{- define "langfuse-bootstrap.substituteVars" -}}
{{- $str := .str }}
{{- $ctx := .ctx }}
{{- if $ctx.Values.environmentConfig }}
{{- $str = $str | replace "${resourcePrefix}" $ctx.Values.environmentConfig.resourcePrefix }}
{{- $str = $str | replace "${region}" $ctx.Values.environmentConfig.region }}
{{- $str = $str | replace "${accountId}" ($ctx.Values.environmentConfig.accountId | toString) }}
{{- end }}
{{- $str }}
{{- end }}

{{/*
Validate required configuration values
*/}}
{{- define "langfuse-bootstrap.validateConfig" -}}
{{- if not .Values.argoProject }}
{{- fail "argoProject is required and cannot be empty" }}
{{- end }}
{{- if not .Values.langfuseChart.version }}
{{- fail "langfuseChart.version is required and cannot be empty" }}
{{- end }}
{{- if not .Values.existingBucketName }}
{{- fail "existingBucketName is required and cannot be empty" }}
{{- end }}
{{- if ne (int .Values.clickhouse.keeper.replicas) 1 }}
{{- if eq (mod (int .Values.clickhouse.keeper.replicas) 2) 0 }}
{{- fail "clickhouse.keeper.replicas must be odd (1, 3, or 5)" }}
{{- end }}
{{- end }}
{{- if .Values.ingress.httpRoute.enabled }}
{{- if not .Values.environmentConfig.clusterFqdn }}
{{- fail "environmentConfig.clusterFqdn is required when ingress.httpRoute.enabled is true" }}
{{- end }}
{{- end }}
{{- if .Values.sso.enabled }}
{{- if not .Values.sso.clientId }}
{{- fail "sso.clientId is required when sso.enabled is true" }}
{{- end }}
{{- if not .Values.sso.issuer }}
{{- fail "sso.issuer is required when sso.enabled is true" }}
{{- end }}
{{- end }}
{{- end }}
