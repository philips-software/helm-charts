{{/*
Expand the name of the chart.
*/}}
{{- define "k8sgpt-bootstrap.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "k8sgpt-bootstrap.fullname" -}}
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
{{- define "k8sgpt-bootstrap.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "k8sgpt-bootstrap.labels" -}}
helm.sh/chart: {{ include "k8sgpt-bootstrap.chart" . }}
{{ include "k8sgpt-bootstrap.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "k8sgpt-bootstrap.selectorLabels" -}}
app.kubernetes.io/name: {{ include "k8sgpt-bootstrap.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Get the IRSA role ARN
*/}}
{{- define "k8sgpt-bootstrap.irsaRoleArn" -}}
{{- if .Values.irsa.roleArn }}
{{- .Values.irsa.roleArn }}
{{- else }}
{{- printf "arn:aws:iam::%v:role/%s-k8sgpt-bedrock-irsa-role" .Values.environmentConfig.accountId .Values.environmentConfig.resourcePrefix }}
{{- end }}
{{- end }}

{{/*
Get the Bedrock region
*/}}
{{- define "k8sgpt-bootstrap.bedrockRegion" -}}
{{- if .Values.k8sgpt.ai.region }}
{{- .Values.k8sgpt.ai.region }}
{{- else }}
{{- .Values.environmentConfig.region }}
{{- end }}
{{- end }}

{{/*
Validate required configuration values
*/}}
{{- define "k8sgpt-bootstrap.validateConfig" -}}
{{- if not .Values.k8sgptOperator.version }}
{{- fail "k8sgptOperator.version is required and cannot be empty" }}
{{- end }}
{{- if not .Values.argoProject }}
{{- fail "argoProject is required and cannot be empty" }}
{{- end }}
{{- if .Values.irsa.enabled }}
{{- if not .Values.irsa.roleArn }}
{{- if not .Values.environmentConfig.accountId }}
{{- fail "environmentConfig.accountId or irsa.roleArn is required when irsa.enabled is true" }}
{{- end }}
{{- if not .Values.environmentConfig.resourcePrefix }}
{{- fail "environmentConfig.resourcePrefix or irsa.roleArn is required when irsa.enabled is true" }}
{{- end }}
{{- if not .Values.environmentConfig.oidcProvider }}
{{- fail "environmentConfig.oidcProvider or irsa.roleArn is required when irsa.enabled is true" }}
{{- end }}
{{- end }}
{{- end }}
{{- if .Values.k8sgpt.enabled }}
{{- if not .Values.k8sgpt.ai.model }}
{{- fail "k8sgpt.ai.model is required when k8sgpt is enabled" }}
{{- end }}
{{- $region := include "k8sgpt-bootstrap.bedrockRegion" . }}
{{- if not $region }}
{{- fail "k8sgpt.ai.region or environmentConfig.region is required when k8sgpt is enabled" }}
{{- end }}
{{- end }}
{{- end }}
