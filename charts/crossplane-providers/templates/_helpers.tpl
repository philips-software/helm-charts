{{/*
Expand the name of the chart.
*/}}
{{- define "crossplane-providers.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "crossplane-providers.fullname" -}}
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
{{- define "crossplane-providers.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "crossplane-providers.labels" -}}
helm.sh/chart: {{ include "crossplane-providers.chart" . }}
{{ include "crossplane-providers.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "crossplane-providers.selectorLabels" -}}
app.kubernetes.io/name: {{ include "crossplane-providers.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Name for the pre-sync cleanup resources (Job, ServiceAccount, ClusterRole, ClusterRoleBinding).
Prefixed with the release name so multiple installations of this chart (e.g. one per provider)
do not collide on these cluster-scoped and shared-namespace resources.
*/}}
{{- define "crossplane-providers.cleanupName" -}}
{{- printf "%s-crossplane-provider-cleanup" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Check if any provider needs IAM resources (has managedPolicyArns or policy, without explicit roleArn)
*/}}
{{- define "crossplane-providers.needsIAMResources" -}}
{{- $needsIAM := false }}
{{- range concat .Values.providers .Values.extraProviders }}
{{- if not (eq (.enabled | toString) "false") }}
{{- if and (or .managedPolicyArns .policy) (not .roleArn) }}
{{- $needsIAM = true }}
{{- end }}
{{- end }}
{{- end }}
{{- $needsIAM }}
{{- end }}

{{/*
Validate required config values
*/}}
{{- define "crossplane-providers.validateConfig" -}}
{{- $needsIAM := include "crossplane-providers.needsIAMResources" . | trim }}
{{- if eq $needsIAM "true" }}
{{- if not .Values.environmentConfig.accountId }}
{{- fail "environmentConfig.accountId is required when providers need IAM resources" }}
{{- end }}
{{- if not .Values.environmentConfig.resourcePrefix }}
{{- fail "environmentConfig.resourcePrefix is required when providers need IAM resources" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Validate OIDC config (only needed when rendering IAM roles)
*/}}
{{- define "crossplane-providers.validateOIDCConfig" -}}
{{- if not .Values.environmentConfig.oidcProviderArn }}
{{- fail "environmentConfig.oidcProviderArn is required when creating IAM roles" }}
{{- end }}
{{- if not .Values.environmentConfig.oidcProvider }}
{{- fail "environmentConfig.oidcProvider is required when creating IAM roles" }}
{{- end }}
{{- end }}
