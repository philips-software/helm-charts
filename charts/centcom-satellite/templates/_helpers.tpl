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
IRSA role name: the Crossplane Role external-name. Generic (not task-specific)
so multiple task-scoped policies can be attached to the same role.
*/}}
{{- define "centcom-satellite.irsaRoleName" -}}
{{- include "centcom-satellite.fullname" . -}}
{{- end }}

{{/*
IRSA role ARN: explicit override, else computed from accountId + path + role name.
The path is normalized via centcom-satellite.irsaPath.
*/}}
{{- define "centcom-satellite.irsaRoleArn" -}}
{{- if .Values.aws.irsa.roleArnOverride -}}
{{- .Values.aws.irsa.roleArnOverride -}}
{{- else -}}
{{- printf "arn:aws:iam::%s:role%s%s" .Values.aws.irsa.accountId (include "centcom-satellite.irsaPath" .) (include "centcom-satellite.irsaRoleName" .) -}}
{{- end -}}
{{- end }}
