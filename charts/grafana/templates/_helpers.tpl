{{/*
Expand the name of the chart.
*/}}
{{- define "grafana.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "grafana.fullname" -}}
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
{{- define "grafana.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "grafana.labels" -}}
helm.sh/chart: {{ include "grafana.chart" . }}
{{ include "grafana.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "grafana.selectorLabels" -}}
app.kubernetes.io/name: {{ include "grafana.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Get the FQDN to use for Grafana.
Uses customFqdn when useCustomFqdn is true, otherwise uses clusterFqdn.
*/}}
{{- define "grafana.fqdn" -}}
{{- if and .Values.useCustomFqdn .Values.environmentConfig.customFqdn }}
{{- .Values.environmentConfig.customFqdn }}
{{- else }}
{{- .Values.environmentConfig.clusterFqdn }}
{{- end }}
{{- end }}

{{/*
Generate the Grafana host (without protocol)
*/}}
{{- define "grafana.host" -}}
{{- if .Values.grafana.httpRoute.enabled }}
{{- printf "%s.%s" .Values.grafana.httpRoute.host (include "grafana.fqdn" .) }}
{{- else }}
{{- printf "%s.%s" .Values.grafana.ingress.host (include "grafana.fqdn" .) }}
{{- end }}
{{- end }}

{{/*
Generate the Grafana URL (external)
*/}}
{{- define "grafana.url" -}}
{{- printf "https://%s" (include "grafana.host" .) }}
{{- end }}

{{/*
Generate the Grafana internal service URL (for in-cluster communication)
*/}}
{{- define "grafana.internalUrl" -}}
{{- printf "http://%s-grafana.%s.svc.cluster.local" .Values.grafanaChart.releaseName .Release.Namespace }}
{{- end }}

{{/*
Validate required configuration values
*/}}
{{- define "grafana.validateConfig" -}}
{{- if not .Values.environmentConfig.clusterFqdn }}
{{- fail "environmentConfig.clusterFqdn is required and cannot be empty" }}
{{- end }}
{{- if not (regexMatch "^[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$" .Values.environmentConfig.clusterFqdn) }}
{{- fail "environmentConfig.clusterFqdn must be a valid domain name (e.g., example.com)" }}
{{- end }}
{{- if not .Values.argocd.project }}
{{- fail "argocd.project is required and cannot be empty" }}
{{- end }}
{{- if .Values.grafana.replicas }}
{{- if not (kindIs "float64" .Values.grafana.replicas) }}
{{- fail "grafana.replicas must be a number" }}
{{- end }}
{{- if lt (.Values.grafana.replicas | int) 1 }}
{{- fail "grafana.replicas must be at least 1" }}
{{- end }}
{{- end }}
{{- if .Values.database.restoreFromSnapshot }}
{{- if not .Values.database.snapshotId }}
{{- fail "database.snapshotId is required when database.restoreFromSnapshot is true" }}
{{- end }}
{{- if not (regexMatch "^[a-zA-Z0-9-]+$" .Values.database.snapshotId) }}
{{- fail "database.snapshotId must contain only alphanumeric characters and hyphens" }}
{{- end }}
{{- end }}
{{- if and .Values.database.cnpg .Values.database.snapshots.enabled }}
{{- if not .Values.database.snapshots.snapshotClassName }}
{{- fail "database.snapshots.snapshotClassName is required when database.snapshots.enabled is true" }}
{{- end }}
{{- end }}
{{- if not (kindIs "bool" .Values.crossplaneProviders.orgmapper.enabled) }}
{{- fail "crossplaneProviders.orgmapper.enabled must be a boolean (true or false)" }}
{{- end }}
{{- if and .Values.grafana.ingress.enabled .Values.grafana.httpRoute.enabled }}
{{- fail "grafana.ingress and grafana.httpRoute are mutually exclusive. Please enable only one of them." }}
{{- end }}
{{- if not .Values.environmentConfig.resourcePrefix }}
{{- fail "environmentConfig.resourcePrefix is required and cannot be empty" }}
{{- end }}
{{- if not .Values.grafanaChart.version }}
{{- fail "grafanaChart.version is required and cannot be empty" }}
{{- end }}
{{- end }}
{{/*
Name for the ArgoCD Applications and the Crossplane providers this chart owns.

These names are CLUSTER-unique, not namespace-unique:

  * The Applications collide with any other release of this chart that targets
    the same argocd.namespace.
  * The Crossplane Provider and DeploymentRuntimeConfig they create are
    cluster-scoped, so they collide with any other release in the cluster no
    matter which namespace it lives in.
  * The upstream Grafana chart's ClusterRole/ClusterRoleBinding are derived from
    grafanaChart.releaseName, so two releases sharing that value collide too.

When two releases claim the same object, both Applications fight over it and
park at OutOfSync with a SharedResourceWarning. Neither ever converges, and
because the pods keep running the Applications can still report Healthy. That
is how a `grafana-test` install silently wedged the production Grafana stack on
ri-obs-use1-dev for two months.

namePrefix defaults to empty, so existing releases keep their current names and
nothing is renamed on upgrade (renaming a finalizer-bearing Application would
cascade-delete the resources it owns). Set namePrefix on any ADDITIONAL release
-- a test install, a second tenant -- to isolate it from the canonical one.
*/}}
{{- define "grafana.resourceName" -}}
{{- $prefix := .ctx.Values.namePrefix | default "" -}}
{{- if $prefix -}}
{{- printf "%s-%s" $prefix .name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- .name -}}
{{- end -}}
{{- end }}
