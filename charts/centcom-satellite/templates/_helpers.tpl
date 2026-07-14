{{/*
Expand the name of the chart.
*/}}
{{- define "centcom-satellite.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "centcom-satellite.fullname" -}}
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
{{- define "centcom-satellite.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "centcom-satellite.labels" -}}
helm.sh/chart: {{ include "centcom-satellite.chart" . }}
{{ include "centcom-satellite.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "centcom-satellite.selectorLabels" -}}
app.kubernetes.io/name: {{ include "centcom-satellite.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "centcom-satellite.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "centcom-satellite.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Normalize IRSA path: ensure it starts and ends with "/".
Inputs → outputs: "" or "/" → "/", "team" → "/team/", "/team" → "/team/",
"team/" → "/team/", "/team/" → "/team/", "team/sub" → "/team/sub/".
*/}}
{{- define "centcom-satellite.irsaPath" -}}
{{- $path := .Values.aws.irsa.path | trimPrefix "/" | trimSuffix "/" -}}
{{- if eq $path "" -}}
{{- "/" -}}
{{- else -}}
{{- printf "/%s/" $path -}}
{{- end -}}
{{- end }}

{{/*
IRSA resource name: the base name for AWS-facing IAM resources (Role, Policy)
provisioned via Crossplane. Unlike Kubernetes object names, an IAM role/policy
name is GLOBAL PER AWS ACCOUNT — so two clusters that share one account and both
install this chart under the same release name would otherwise fight over the
identical role/policy name. aws.irsa.namePrefix disambiguates them (install.sh
seeds it from the cluster's environment tag). Empty prefix == fullname, so
existing installs are unaffected.
*/}}
{{- define "centcom-satellite.irsaName" -}}
{{- $prefix := .Values.aws.irsa.namePrefix | default "" | trimPrefix "-" | trimSuffix "-" -}}
{{- if $prefix -}}
{{- printf "%s-%s" $prefix (include "centcom-satellite.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- include "centcom-satellite.fullname" . -}}
{{- end -}}
{{- end }}

{{/*
IRSA role name: the Crossplane Role external-name. Generic (not task-specific)
so multiple task-scoped policies can be attached to the same role. Prefixed via
centcom-satellite.irsaName for account-global uniqueness.
*/}}
{{- define "centcom-satellite.irsaRoleName" -}}
{{- include "centcom-satellite.irsaName" . -}}
{{- end }}

{{/*
IRSA role ARN: explicit override, else computed from accountId + path + role name.
The path is normalized via centcom-satellite.irsaPath.
*/}}
{{- define "centcom-satellite.irsaRoleArn" -}}
{{- if .Values.aws.irsa.roleArnOverride -}}
{{- .Values.aws.irsa.roleArnOverride -}}
{{- else -}}
{{- /* toString guards against Helm coercing a numeric accountId to int64 (a
       12-digit id without a leading zero), which would make %s emit
       %!s(int64=...). */ -}}
{{- printf "arn:aws:iam::%s:role%s%s" (.Values.aws.irsa.accountId | toString) (include "centcom-satellite.irsaPath" .) (include "centcom-satellite.irsaRoleName" .) -}}
{{- end -}}
{{- end }}
