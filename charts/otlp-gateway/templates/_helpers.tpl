{{/*
Expand the name of the chart.
*/}}
{{- define "otlp-gateway.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "otlp-gateway.fullname" -}}
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
{{- define "otlp-gateway.chart" -}}
{{- if index .Values "$chart_tests" }}
{{- printf "%s" .Chart.Name | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Allow the release namespace to be overridden for multi-namespace deployments in combined charts
*/}}
{{- define "otlp-gateway.namespace" -}}
{{- if .Values.namespaceOverride }}
{{- .Values.namespaceOverride }}
{{- else }}
{{- .Release.Namespace }}
{{- end }}
{{- end }}


{{/*
Calculate name of image ID to use for "alloy.
*/}}
{{- define "otlp-gateway.imageId" -}}
{{- if .Values.image.digest }}
{{- $digest := .Values.image.digest }}
{{- if not (hasPrefix "sha256:" $digest) }}
{{- $digest = printf "sha256:%s" $digest }}
{{- end }}
{{- printf "@%s" $digest }}
{{- else if .Values.image.tag }}
{{- printf ":%s" .Values.image.tag }}
{{- else }}
{{- printf ":%s" .Chart.AppVersion }}
{{- end }}
{{- end }}

{{/*
Generate the name for the signed tokens secret.
If name is provided in values, use it. Otherwise, generate a consistent name.
*/}}
{{- define "otlp-gateway.signedTokensSecretName" -}}
{{- if .Values.authn.signedTokens.secret }}
{{- .Values.authn.signedTokens.secret }}
{{- else }}
{{- printf "%s-otlp-gateway-signing-key" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Generate the name for the client CA secret.
If name is provided in values, use it. Otherwise, generate a consistent name.
*/}}
{{- define "otlp-gateway.clientCaSecretName" -}}
{{- if .Values.authn.clientCa.secret }}
{{- .Values.authn.clientCa.secret }}
{{- else }}
{{- printf "%s-otlp-gateway-client-ca" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Validate required configuration values
*/}}
{{- define "otlp-gateway.validateConfig" -}}
{{- if .Values.loadbalancer.enabled }}
{{- if not .Values.environmentConfig.clusterFqdn }}
{{- fail "environmentConfig.clusterFqdn is required when loadbalancer.enabled is true" }}
{{- end }}
{{- if not (regexMatch "^[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$" .Values.environmentConfig.clusterFqdn) }}
{{- fail "environmentConfig.clusterFqdn must be a valid domain name (e.g., gateway.example.com)" }}
{{- end }}
{{- end }}
{{- if not .Values.environmentConfig.host }}
{{- fail "environmentConfig.host is required and cannot be empty" }}
{{- end }}
{{- if not (regexMatch "^[a-zA-Z0-9-]+$" .Values.environmentConfig.host) }}
{{- fail "environmentConfig.host must contain only alphanumeric characters and hyphens" }}
{{- end }}
{{- if not (kindIs "float64" .Values.replicas) }}
{{- fail "replicas must be a number" }}
{{- end }}
{{- if lt (.Values.replicas | int) 1 }}
{{- fail "replicas must be at least 1" }}
{{- end }}
{{- if .Values.autoscaling.enabled }}
{{- if not (kindIs "float64" .Values.autoscaling.minReplicas) }}
{{- fail "autoscaling.minReplicas must be a number" }}
{{- end }}
{{- if not (kindIs "float64" .Values.autoscaling.maxReplicas) }}
{{- fail "autoscaling.maxReplicas must be a number" }}
{{- end }}
{{- if lt (.Values.autoscaling.minReplicas | int) 1 }}
{{- fail "autoscaling.minReplicas must be at least 1" }}
{{- end }}
{{- if le (.Values.autoscaling.maxReplicas | int) (.Values.autoscaling.minReplicas | int) }}
{{- fail "autoscaling.maxReplicas must be greater than autoscaling.minReplicas" }}
{{- end }}
{{- if not (and (ge (.Values.autoscaling.targetCPUUtilizationPercentage | int) 1) (le (.Values.autoscaling.targetCPUUtilizationPercentage | int) 100)) }}
{{- fail "autoscaling.targetCPUUtilizationPercentage must be between 1 and 100" }}
{{- end }}
{{- if not (and (ge (.Values.autoscaling.targetMemoryUtilizationPercentage | int) 1) (le (.Values.autoscaling.targetMemoryUtilizationPercentage | int) 100)) }}
{{- fail "autoscaling.targetMemoryUtilizationPercentage must be between 1 and 100" }}
{{- end }}
{{- end }}
{{- if .Values.authn.oidc.enabled }}
{{- if not .Values.authn.oidc.issuer }}
{{- fail "authn.oidc.issuer is required when authn.oidc.enabled is true" }}
{{- end }}
{{- if not (regexMatch "^https://.*" .Values.authn.oidc.issuer) }}
{{- fail "authn.oidc.issuer must be a valid HTTPS URL" }}
{{- end }}
{{- end }}
{{- if not (has .Values.log.level (list "debug" "info" "warn" "error")) }}
{{- fail "log.level must be one of: debug, info, warn, error" }}
{{- end }}
{{- end }}
