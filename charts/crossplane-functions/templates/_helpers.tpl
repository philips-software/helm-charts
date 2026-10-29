{{/*
Expand the name of the chart.
*/}}
{{- define "crossplane-functions.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "crossplane-functions.fullname" -}}
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
{{- define "crossplane-functions.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "crossplane-functions.labels" -}}
helm.sh/chart: {{ include "crossplane-functions.chart" . }}
{{ include "crossplane-functions.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ include "crossplane-functions.managedBy" . }}
{{- include "crossplane-functions.ownerLabels" . }}
{{- end }}

{{/*
Owner label rendered from environmentConfig.owner so workloads satisfy the
require-owner-label Kyverno policy. Omitted when unset.
*/}}
{{- define "crossplane-functions.ownerLabels" -}}
{{- if .Values.environmentConfig.owner }}
owner: {{ .Values.environmentConfig.owner | quote }}
{{- end }}
{{- end }}

{{/*
Value for the app.kubernetes.io/managed-by label, overridden by
environmentConfig.managedBy when set.
*/}}
{{- define "crossplane-functions.managedBy" -}}
{{- .Values.environmentConfig.managedBy | default .Release.Service -}}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "crossplane-functions.selectorLabels" -}}
app.kubernetes.io/name: {{ include "crossplane-functions.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
